import AVFoundation
import Foundation

@MainActor
final class LatencyTestViewModel: ObservableObject {
    @Published private(set) var isSessionActive = false
    @Published private(set) var route = AudioRouteDescription.unavailable
    @Published private(set) var measurements: [CueLatencyMeasurement] = []
    @Published var errorMessage: String?

    private let audioSession = AudioSessionManager()
    private let cuePlayer = CuePlayer()

    init() {
        cuePlayer.onMeasurement = { [weak self] measurement in
            self?.measurements.append(measurement)
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

    func toggleSession() {
        isSessionActive ? stopSession() : startSession()
    }

    func playCue() {
        guard isSessionActive else { return }
        cuePlayer.playCachedCue()
    }

    func resetMeasurements() {
        measurements.removeAll()
    }

    private func startSession() {
        errorMessage = nil

        Task {
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
        isSessionActive = false
    }

    private func percentile(_ fraction: Double) -> Double? {
        let values = measurements.map(\.milliseconds).sorted()
        guard !values.isEmpty else { return nil }

        let index = Int(ceil(Double(values.count) * fraction)) - 1
        return values[max(0, min(index, values.count - 1))]
    }
}

