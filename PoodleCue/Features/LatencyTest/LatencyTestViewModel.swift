import AVFoundation
import Foundation
import Speech

@MainActor
final class LatencyTestViewModel: ObservableObject {
    @Published private(set) var isSessionActive = false
    @Published private(set) var isStartingSession = false
    @Published private(set) var route = AudioRouteDescription.unavailable
    @Published private(set) var measurements: [CueLatencyMeasurement] = []
    @Published private(set) var microphoneLevelDBFS = -80.0
    @Published private(set) var isSpeechActive = false
    @Published private(set) var speechDetectionLatencies: [Double] = []
    @Published private(set) var transcript = ""
    @Published private(set) var transcriptionLocale = ""
    @Published private(set) var transcriptionLatencies: [Double] = []
    @Published private(set) var isTranscriptFinal = false
    @Published private(set) var latestCue: LocalConversationCue?
    @Published private(set) var cueCount = 0
    @Published private(set) var cueSpeechStartMilliseconds: Double?
    @Published var speaksCues = true
    @Published var errorMessage: String?

    private let audioSession = AudioSessionManager()
    private let cuePlayer = CuePlayer()
    private let transcriber = SpeechTranscriber()
    private let cueEngine = LocalCueEngine()
    private let cueSpeaker = CueSpeaker()
    private var pendingSpeechOnsetNanoseconds: UInt64?
    private var needsCueForCurrentUtterance = false

    init() {
        cuePlayer.onMeasurement = { [weak self] measurement in
            self?.measurements.append(measurement)
        }
        cuePlayer.onSpeechActivity = { [weak self] snapshot in
            guard let self else { return }
            let wasSpeechActive = isSpeechActive
            microphoneLevelDBFS = snapshot.levelDBFS
            isSpeechActive = snapshot.isSpeechActive

            if let latency = snapshot.onsetLatencyMilliseconds {
                speechDetectionLatencies.append(latency)
                pendingSpeechOnsetNanoseconds = DispatchTime.now().uptimeNanoseconds
                needsCueForCurrentUtterance = true
            }

            if wasSpeechActive && !snapshot.isSpeechActive {
                createCueIfReady()
            }
        }
        cuePlayer.onAudioBuffer = { [weak self] buffer in
            self?.transcriber.append(buffer)
        }
        transcriber.onTranscript = { [weak self] text, isFinal in
            DispatchQueue.main.async {
                self?.receiveTranscript(text, isFinal: isFinal)
            }
        }
        transcriber.onError = { [weak self] message in
            DispatchQueue.main.async {
                self?.errorMessage = message
            }
        }
        let cueSpeaker = cueSpeaker
        cuePlayer.shouldSuppressInput = { [weak cueSpeaker] in
            cueSpeaker?.isSpeaking ?? false
        }
        cueSpeaker.onSpeechStarted = { [weak self] latency in
            DispatchQueue.main.async {
                self?.cueSpeechStartMilliseconds = latency
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

    var transcriptionLatest: Double? {
        transcriptionLatencies.last
    }

    var transcriptionMedian: Double? {
        percentile(0.50, values: transcriptionLatencies)
    }

    var transcriptionP95: Double? {
        percentile(0.95, values: transcriptionLatencies)
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

    func replayLatestCue() {
        guard let latestCue else { return }
        cueSpeaker.speak(latestCue.text)
    }

    private func startSession() {
        errorMessage = nil
        isStartingSession = true
        measurements.removeAll()
        speechDetectionLatencies.removeAll()
        transcriptionLatencies.removeAll()
        transcript = ""
        transcriptionLocale = ""
        isTranscriptFinal = false
        pendingSpeechOnsetNanoseconds = nil
        needsCueForCurrentUtterance = false
        latestCue = nil
        cueCount = 0
        cueSpeechStartMilliseconds = nil
        cueEngine.reset()
        cueSpeaker.stop()
        microphoneLevelDBFS = -80
        isSpeechActive = false

        Task {
            defer { isStartingSession = false }
            let permission = await AVAudioApplication.requestRecordPermission()
            guard permission else {
                errorMessage = "Microphone permission is required to activate the duplex audio session."
                return
            }

            let speechPermission = await requestSpeechRecognitionPermission()
            guard speechPermission else {
                errorMessage = "Speech recognition permission is required for live on-device transcription."
                return
            }

            do {
                route = try audioSession.activate()
                transcriptionLocale = try transcriber.start()
                try cuePlayer.prepare()
                isSessionActive = true
            } catch {
                transcriber.stop()
                cuePlayer.stop()
                audioSession.deactivate()
                errorMessage = error.localizedDescription
            }
        }
    }

    private func stopSession() {
        cueSpeaker.stop()
        transcriber.stop()
        cuePlayer.stop()
        audioSession.deactivate()
        route = .unavailable
        microphoneLevelDBFS = -80
        isSpeechActive = false
        pendingSpeechOnsetNanoseconds = nil
        needsCueForCurrentUtterance = false
        isSessionActive = false
    }

    private func receiveTranscript(_ text: String, isFinal: Bool) {
        transcript = text
        isTranscriptFinal = isFinal

        if let startedAt = pendingSpeechOnsetNanoseconds {
            let now = DispatchTime.now().uptimeNanoseconds
            let elapsed = now > startedAt ? now - startedAt : 0
            transcriptionLatencies.append(Double(elapsed) / 1_000_000)
            pendingSpeechOnsetNanoseconds = nil
        }

        if !isSpeechActive {
            createCueIfReady()
        }
    }

    private func createCueIfReady() {
        guard
            needsCueForCurrentUtterance,
            let cue = cueEngine.suggest(from: transcript)
        else { return }

        latestCue = cue
        cueCount += 1
        cueSpeechStartMilliseconds = nil
        needsCueForCurrentUtterance = false

        if speaksCues {
            cueSpeaker.speak(cue.text)
        }
    }

    private func requestSpeechRecognitionPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
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

