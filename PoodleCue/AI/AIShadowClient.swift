import Foundation

private struct AIShadowConfiguration {
    let endpoint: URL?
    let appToken: String?

    init(bundle: Bundle) {
        let endpointText = bundle.object(forInfoDictionaryKey: "AIShadowEndpoint") as? String
        let tokenText = bundle.object(forInfoDictionaryKey: "AIShadowAppToken") as? String

        if let endpointText,
           !endpointText.isEmpty,
           !endpointText.contains("$("),
           let url = URL(string: endpointText) {
            endpoint = url
        } else {
            endpoint = nil
        }

        if let tokenText, !tokenText.isEmpty, !tokenText.contains("$(") {
            appToken = tokenText
        } else {
            appToken = nil
        }
    }

    var realtimeTokenEndpoint: URL? {
        endpoint?.deletingLastPathComponent().appendingPathComponent("realtime-token")
    }
}

struct AIShadowCue: Decodable, Equatable {
    let shouldSpeak: Bool
    let cue: String
    let intent: String
    let reason: String
    let confidence: Double
    let latencyMilliseconds: Double

    enum CodingKeys: String, CodingKey {
        case shouldSpeak = "should_speak"
        case cue
        case intent
        case reason
        case confidence
        case latencyMilliseconds = "latency_ms"
    }
}

enum AIShadowState: Equatable {
    case unavailable
    case idle
    case comparing
    case ready(AIShadowCue)
    case failed(String)
}

struct AIShadowRequest: Encodable {
    let them: String
    let me: String?
    let memory: String?
    let recentCues: [String]

    enum CodingKeys: String, CodingKey {
        case them
        case me
        case memory
        case recentCues = "recent_cues"
    }
}

final class AIShadowClient {
    private let endpoint: URL?
    private let appToken: String?
    private let session: URLSession

    var isConfigured: Bool { endpoint != nil }

    init(bundle: Bundle = .main) {
        let configurationValues = AIShadowConfiguration(bundle: bundle)
        endpoint = configurationValues.endpoint
        appToken = configurationValues.appToken

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8.5
        configuration.timeoutIntervalForResource = 9.0
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func compare(_ payload: AIShadowRequest) async throws -> AIShadowCue {
        guard let endpoint else {
            throw AIShadowError.notConfigured
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let appToken {
            request.setValue("Bearer \(appToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIShadowError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AIShadowError.server(httpResponse.statusCode)
        }
        return try JSONDecoder().decode(AIShadowCue.self, from: data)
    }
}

@MainActor
final class AIRealtimeClient {
    private struct ClientCredential: Decodable {
        let value: String
        let expiresAt: Int
        let model: String

        enum CodingKeys: String, CodingKey {
            case value
            case expiresAt = "expires_at"
            case model
        }
    }

    private struct ServerEvent: Decodable {
        let type: String
        let text: String?
        let error: ServerError?
    }

    private struct ServerError: Decodable {
        let message: String?
    }

    private struct GeneratedCue: Decodable {
        let shouldSpeak: Bool
        let cue: String
        let intent: String
        let reason: String
        let confidence: Double

        enum CodingKeys: String, CodingKey {
            case shouldSpeak = "should_speak"
            case cue
            case intent
            case reason
            case confidence
        }
    }

    private struct PendingResponse {
        let startedAt: ContinuousClock.Instant
        let continuation: CheckedContinuation<AIShadowCue, Error>
    }

    private let tokenEndpoint: URL?
    private let appToken: String?
    private let tokenSession: URLSession
    private var webSocketSession: URLSession?
    private var webSocket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var pendingResponse: PendingResponse?

    var isConfigured: Bool { tokenEndpoint != nil && appToken != nil }
    var isConnected: Bool { webSocket != nil }

    init(bundle: Bundle = .main) {
        let values = AIShadowConfiguration(bundle: bundle)
        tokenEndpoint = values.realtimeTokenEndpoint
        appToken = values.appToken

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 6
        configuration.waitsForConnectivity = false
        tokenSession = URLSession(configuration: configuration)
    }

    func connect() async throws {
        guard webSocket == nil else { return }
        guard let tokenEndpoint, let appToken else {
            throw AIShadowError.notConfigured
        }

        var tokenRequest = URLRequest(url: tokenEndpoint)
        tokenRequest.httpMethod = "POST"
        tokenRequest.setValue("Bearer \(appToken)", forHTTPHeaderField: "Authorization")
        tokenRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        tokenRequest.httpBody = Data("{}".utf8)

        let (data, response) = try await tokenSession.data(for: tokenRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIShadowError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AIShadowError.server(httpResponse.statusCode)
        }

        let credential = try JSONDecoder().decode(ClientCredential.self, from: data)
        guard var components = URLComponents(string: "wss://api.openai.com/v1/realtime") else {
            throw AIShadowError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "model", value: credential.model)]
        guard let realtimeURL = components.url else {
            throw AIShadowError.invalidResponse
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        let socket = session.webSocketTask(
            with: realtimeURL,
            protocols: [
                "realtime",
                "openai-insecure-api-key.\(credential.value)",
            ]
        )
        webSocketSession = session
        webSocket = socket
        socket.resume()
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func disconnect() {
        receiveTask?.cancel()
        timeoutTask?.cancel()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        webSocketSession?.invalidateAndCancel()
        webSocketSession = nil
        failPending(with: CancellationError())
    }

    func compare(_ payload: AIShadowRequest) async throws -> AIShadowCue {
        if webSocket == nil {
            try await connect()
        }
        guard let webSocket else {
            throw AIShadowError.invalidResponse
        }

        failPending(with: CancellationError())
        let requestID = UUID().uuidString
        let payloadData = try JSONEncoder().encode(payload)
        guard let payloadText = String(data: payloadData, encoding: .utf8) else {
            throw AIShadowError.invalidResponse
        }

        let event: [String: Any] = [
            "type": "response.create",
            "event_id": requestID,
            "response": [
                "conversation": "none",
                "output_modalities": ["text"],
                "metadata": ["request_id": requestID],
                "instructions": "Evaluate this completed conversation turn. Return only the required compact JSON object, with no markdown or extra text.",
                "input": [[
                    "type": "message",
                    "role": "user",
                    "content": [["type": "input_text", "text": payloadText]],
                ]],
            ],
        ]
        let eventData = try JSONSerialization.data(withJSONObject: event)
        guard let eventText = String(data: eventData, encoding: .utf8) else {
            throw AIShadowError.invalidResponse
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingResponse = PendingResponse(startedAt: .now, continuation: continuation)
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.failPending(with: AIRealtimeError.timedOut)
            }
            Task { [weak self] in
                do {
                    try await webSocket.send(.string(eventText))
                } catch {
                    self?.failPending(with: error)
                }
            }
        }
    }

    private func receiveLoop() async {
        guard let webSocket else { return }
        do {
            while !Task.isCancelled {
                let message = try await webSocket.receive()
                let data: Data
                switch message {
                case let .data(value): data = value
                case let .string(value): data = Data(value.utf8)
                @unknown default: continue
                }
                handleServerEvent(data)
            }
        } catch {
            if !Task.isCancelled {
                failPending(with: error)
            }
            self.webSocket = nil
            webSocketSession?.invalidateAndCancel()
            webSocketSession = nil
        }
    }

    private func handleServerEvent(_ data: Data) {
        guard let event = try? JSONDecoder().decode(ServerEvent.self, from: data) else { return }
        switch event.type {
        case "response.output_text.done":
            guard let text = event.text else {
                failPending(with: AIShadowError.invalidResponse)
                return
            }
            finishPending(with: text)
        case "error":
            failPending(with: AIRealtimeError.server(event.error?.message ?? "Realtime request failed."))
        default:
            break
        }
    }

    private func finishPending(with rawText: String) {
        guard let pendingResponse else { return }
        do {
            let jsonText = extractJSONObject(from: rawText)
            let value = try JSONDecoder().decode(GeneratedCue.self, from: Data(jsonText.utf8))
            let elapsed = pendingResponse.startedAt.duration(to: .now)
            let components = elapsed.components
            let milliseconds = Double(components.seconds) * 1_000
                + Double(components.attoseconds) / 1_000_000_000_000_000
            let cue = AIShadowCue(
                shouldSpeak: value.shouldSpeak && !value.cue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                cue: value.shouldSpeak ? String(value.cue.prefix(160)) : "",
                intent: value.intent,
                reason: String(value.reason.prefix(240)),
                confidence: min(max(value.confidence, 0), 1),
                latencyMilliseconds: milliseconds
            )
            timeoutTask?.cancel()
            timeoutTask = nil
            self.pendingResponse = nil
            pendingResponse.continuation.resume(returning: cue)
        } catch {
            failPending(with: error)
        }
    }

    private func failPending(with error: Error) {
        guard let pendingResponse else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        self.pendingResponse = nil
        pendingResponse.continuation.resume(throwing: error)
    }

    private func extractJSONObject(from text: String) -> String {
        guard let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}") else {
            return text
        }
        return String(text[first...last])
    }
}

enum AIRealtimeError: LocalizedError {
    case timedOut
    case server(String)

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "The warmed AI connection timed out."
        case let .server(message):
            return message
        }
    }
}

enum AIShadowError: LocalizedError {
    case notConfigured
    case invalidResponse
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI shadow mode is not configured."
        case .invalidResponse:
            return "The AI comparison service returned an invalid response."
        case let .server(status):
            return "The AI comparison service returned status \(status)."
        }
    }
}
