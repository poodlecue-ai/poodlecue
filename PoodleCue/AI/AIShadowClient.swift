import Foundation

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
