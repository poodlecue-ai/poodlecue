import AVFoundation
import Foundation
import Speech

struct ConversationTurn: Identifiable, Equatable {
    enum Speaker: String {
        case me = "Me"
        case them = "Them"
    }

    let id = UUID()
    let speaker: Speaker
    let text: String
}

enum CueFeedback: String, CaseIterable {
    case useful = "Useful"
    case notUseful = "Not useful"
    case tooLate = "Too late"
    case repeated = "Repeated"
}

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
    @Published private(set) var conversationTurns: [ConversationTurn] = []
    @Published private(set) var latestCueFeedback: CueFeedback?
    @Published private(set) var aiShadowState: AIShadowState = .unavailable
    @Published private(set) var aiComparisonChoice: String?
    @Published private(set) var localShadowBaseline: String?
    @Published var speaksCues = true
    @Published var inputPreference: AudioInputPreference = .iPhone
    @Published var listeningToOtherPerson = true {
        didSet {
            guard listeningToOtherPerson != oldValue else { return }
            speakerRoleChanged(from: oldValue)
        }
    }
    @Published var conversationPartnerName = ""
    @Published var memoryDraft = ""
    @Published private(set) var selectedMemory: ConversationMemory?
    @Published private(set) var memoryStatusMessage: String?
    @Published var errorMessage: String?

    private let audioSession = AudioSessionManager()
    private let cuePlayer = CuePlayer()
    private let transcriber = SpeechTranscriber()
    private let cueEngine = LocalCueEngine()
    private let cueSpeaker = CueSpeaker()
    private let aiShadowClient = AIShadowClient()
    let memoryStore = ConversationMemoryStore()
    private var pendingSpeechOnsetNanoseconds: UInt64?
    private var needsCueForCurrentUtterance = false
    private var roleStartTranscript = ""
    private var previousUserTurn: String?
    private var recentCueTexts: [String] = []
    private var aiShadowTask: Task<Void, Never>?

    init() {
        aiShadowState = aiShadowClient.isConfigured ? .idle : .unavailable
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
                needsCueForCurrentUtterance = listeningToOtherPerson
            }

            if wasSpeechActive && !snapshot.isSpeechActive {
                if listeningToOtherPerson {
                    createCueIfReady()
                } else {
                    captureUserTurn()
                }
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

    var isAIShadowConfigured: Bool {
        aiShadowClient.isConfigured
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

    func recordCueFeedback(_ feedback: CueFeedback) {
        guard latestCue != nil else { return }
        latestCueFeedback = feedback
        let key = "cueFeedback.\(feedback.rawValue)"
        let total = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(total, forKey: key)
    }

    func recordAIComparison(_ choice: String) {
        let validChoices = ["Local", "AI", "Neither"]
        guard case .ready = aiShadowState,
              validChoices.contains(choice),
              aiComparisonChoice != choice else { return }

        if let previousChoice = aiComparisonChoice {
            let previousKey = "aiComparison.\(previousChoice)"
            let previousTotal = UserDefaults.standard.integer(forKey: previousKey)
            UserDefaults.standard.set(max(0, previousTotal - 1), forKey: previousKey)
        }

        aiComparisonChoice = choice
        let key = "aiComparison.\(choice)"
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
    }

    func selectMemory(_ memory: ConversationMemory) {
        selectedMemory = memory
        conversationPartnerName = memory.personName
        memoryDraft = memory.summary
        latestCue = cueEngine.followUpCue(
            personName: memory.personName,
            summary: memory.summary
        )
        latestCueFeedback = nil
        aiShadowTask?.cancel()
        aiShadowState = aiShadowClient.isConfigured ? .idle : .unavailable
        aiComparisonChoice = nil
        localShadowBaseline = nil
        memoryStatusMessage = "Ready with context from your last conversation."
    }

    func beginNewConversation() {
        guard !isSessionActive else { return }
        selectedMemory = nil
        conversationPartnerName = ""
        memoryDraft = ""
        latestCue = nil
        latestCueFeedback = nil
        aiShadowTask?.cancel()
        aiShadowState = aiShadowClient.isConfigured ? .idle : .unavailable
        aiComparisonChoice = nil
        localShadowBaseline = nil
        memoryStatusMessage = nil
    }

    func prepareMemoryDraft() {
        let draft = MemorySummaryBuilder.draft(from: transcript)
        if draft.isEmpty {
            memoryStatusMessage = "Have a conversation first, or type a note yourself."
        } else {
            memoryDraft = draft
            memoryStatusMessage = "Review this note before saving it."
        }
    }

    func saveMemory() {
        guard let saved = memoryStore.save(
            personName: conversationPartnerName,
            summary: memoryDraft
        ) else {
            memoryStatusMessage = "Add the person’s name and a short note first."
            return
        }
        selectedMemory = saved
        memoryStatusMessage = "Saved privately on this iPhone."
    }

    func forgetSelectedMemory() {
        guard let selectedMemory else { return }
        memoryStore.delete(selectedMemory)
        self.selectedMemory = nil
        conversationPartnerName = ""
        memoryDraft = ""
        memoryStatusMessage = "Memory removed from this iPhone."
    }

    private func speakerRoleChanged(from previousRoleWasOther: Bool) {
        if !previousRoleWasOther {
            captureUserTurn()
        }
        pendingSpeechOnsetNanoseconds = nil
        needsCueForCurrentUtterance = false
        cueEngine.beginTurn(at: transcript)
        roleStartTranscript = transcript

        if listeningToOtherPerson, isSessionActive {
            latestCue = nil
            latestCueFeedback = nil
        }
    }

    private func captureUserTurn() {
        let text = transcriptDelta(since: roleStartTranscript)
        guard !text.isEmpty else { return }
        previousUserTurn = text
        appendTurn(speaker: .me, text: text)
        roleStartTranscript = transcript
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
        conversationTurns = []
        latestCueFeedback = nil
        aiShadowTask?.cancel()
        aiShadowState = aiShadowClient.isConfigured ? .idle : .unavailable
        aiComparisonChoice = nil
        localShadowBaseline = nil
        roleStartTranscript = ""
        previousUserTurn = nil
        recentCueTexts = []
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
                route = try audioSession.activate(inputPreference: inputPreference)
                transcriptionLocale = try transcriber.start()
                try cuePlayer.prepare()
                isSessionActive = true
                if let selectedMemory {
                    let cue = cueEngine.followUpCue(
                        personName: selectedMemory.personName,
                        summary: selectedMemory.summary
                    )
                    latestCue = cue
                    cueCount = 1
                    recentCueTexts.append(cue.text)
                    if speaksCues {
                        cueSpeaker.speak(cue.text)
                    }
                }
            } catch {
                transcriber.stop()
                cuePlayer.stop()
                audioSession.deactivate()
                errorMessage = error.localizedDescription
            }
        }
    }

    private func stopSession() {
        aiShadowTask?.cancel()
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
        guard listeningToOtherPerson, needsCueForCurrentUtterance else { return }

        let themText = transcriptDelta(since: roleStartTranscript)
        guard !themText.isEmpty else { return }

        let cue = cueEngine.suggest(
                from: transcript,
                memorySummary: selectedMemory?.summary,
                previousUserTurn: previousUserTurn,
                recentCueTexts: recentCueTexts
            )
        needsCueForCurrentUtterance = false
        latestCue = cue
        latestCueFeedback = nil
        localShadowBaseline = cue?.text ?? "Stay silent"

        appendTurn(speaker: .them, text: themText)
        roleStartTranscript = transcript

        if let cue {
            cueCount += 1
            cueSpeechStartMilliseconds = nil
            recentCueTexts.append(cue.text)
            recentCueTexts = Array(recentCueTexts.suffix(5))

            if speaksCues {
                cueSpeaker.speak(cue.text)
            }
        }

        requestAIShadowCue(themText: themText, localCue: cue?.text)
    }

    private func requestAIShadowCue(themText: String, localCue: String?) {
        guard aiShadowClient.isConfigured else { return }
        let payload = AIShadowRequest(
            them: themText,
            me: previousUserTurn,
            memory: selectedMemory?.summary,
            recentCues: recentCueTexts,
            localCue: localCue
        )

        aiShadowTask?.cancel()
        aiShadowState = .comparing
        aiComparisonChoice = nil
        aiShadowTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await aiShadowClient.compare(payload)
                guard !Task.isCancelled else { return }
                aiShadowState = .ready(result)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                aiShadowState = .failed("AI comparison unavailable; your local cue was unaffected.")
            }
        }
    }

    private func appendTurn(speaker: ConversationTurn.Speaker, text: String) {
        guard conversationTurns.last?.text != text else { return }
        conversationTurns.append(ConversationTurn(speaker: speaker, text: text))
        conversationTurns = Array(conversationTurns.suffix(12))
    }

    private func transcriptDelta(since baseline: String) -> String {
        let text: String
        if transcript.hasPrefix(baseline) {
            text = String(transcript.dropFirst(baseline.count))
        } else {
            text = transcript
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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

