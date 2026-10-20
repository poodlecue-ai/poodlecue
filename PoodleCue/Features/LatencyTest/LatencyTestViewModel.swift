import AVFoundation
import Foundation

@MainActor
final class LatencyTestViewModel: ObservableObject {
    @Published private(set) var isSessionActive = false
    @Published private(set) var isStartingSession = false
    @Published private(set) var route = AudioRouteDescription.unavailable
    @Published private(set) var measurements: [CueLatencyMeasurement] = []
    @Published private(set) var microphoneLevelDBFS = -80.0
    @Published private(set) var isSpeechActive = false
    @Published private(set) var speechDetectionLatencies: [Double] = []
    @Published var errorMessage: String?

    private let audioSession = AudioSessionManager()
    private let cuePlayer = CuePlayer()

    init() {
        cuePlayer.onMeasurement = { [weak self] measurement in
            self?.measurements.append(measurement)
        }
        cuePlayer.onSpeechActivity = { [weak self] snapshot in
            guard let self else { return }
            microphoneLevelDBFS = snapshot.levelDBFS
            isSpeechActive = snapshot.isSpeechActive

            if let latency = snapshot.onsetLatencyMilliseconds {
                speechDetectionLatencies.append(latency)
            }
        }
    }

    var latestLatency: Double? {
        latestMeasurement?.milliseconds
    }

    var latestMeasurement: CueLatencyMeasurement? {
        measurements.last
    }

    var medianLatency: Double? {
        percentile(0.50)
    }

    var p95Latency: Double? {
        percentile(0.95)
    }

    var passesTarget: Bool? {
        guard measurements.count >= 20, let p95Latency else { return nil }
        return p95Latency < 200
    }

    var speechDetectionLatest: Double? {
        speechDetectionLatencies.last
    }

    var speechDetectionMedian: Double? {
        percentile(0.50, values: speechDetectionLatencies)
    }

    var speechDetectionP95: Double? {
        percentile(0.95, values: speechDetectionLatencies)
    }

    var normalizedMicrophoneLevel: Double {
        min(max((microphoneLevelDBFS + 60) / 60, 0), 1)
    }

    func toggleSession() {
        guard !isStartingSession else { return }
        isSessionActive ? stopSession() : startSession()
    }

    func playCue() {
        guard isSessionActive else { return }
        cuePlayer.playCachedCue()
    }

    func resetMeasurements() {
        measurements.removeAll()
    }

    func resetSpeechMeasurements() {
        speechDetectionLatencies.removeAll()
    }

    private func startSession() {
        errorMessage = nil
        isStartingSession = true
        measurements.removeAll()
        speechDetectionLatencies.removeAll()
        microphoneLevelDBFS = -80
        isSpeechActive = false

        Task {
            defer { isStartingSession = false }
            let permission = await AVAudioApplication.requestRecordPermission()
            guard permission else {
                errorMessage = "Microphone permission is required to activate the duplex audio session."
                return
            }

            do {
                route = try audioSession.activate()
                try cuePlayer.prepare()
                isSessionActive = true
            } catch {
                cuePlayer.stop()
                audioSession.deactivate()
                errorMessage = error.localizedDescription
            }
        }
    }

    private func stopSession() {
        cuePlayer.stop()
        audioSession.deactivate()
        route = .unavailable
        microphoneLevelDBFS = -80
        isSpeechActive = false
        isSessionActive = false
    }

    private func percentile(_ fraction: Double) -> Double? {
        percentile(fraction, values: measurements.map(\.milliseconds))
    }

    private func percentile(_ fraction: Double, values: [Double]) -> Double? {
        let values = values.sorted()
        guard !values.isEmpty else { return nil }

        let index = Int(ceil(Double(values.count) * fraction)) - 1
        return values[max(0, min(index, values.count - 1))]
    }
}

