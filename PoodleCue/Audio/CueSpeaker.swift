import AVFoundation

final class CueSpeaker: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private let stateLock = NSLock()
    private var speaking = false
    private var requestedAtNanoseconds: UInt64 = 0

    var onSpeechStarted: ((Double) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }

    var isSpeaking: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return speaking
    }

    func speak(_ text: String) {
        guard !text.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.preferredFeminineVoice()
        utterance.rate = 0.44
        utterance.pitchMultiplier = 1.08
        utterance.volume = 0.78
        utterance.preUtteranceDelay = 0.03
        utterance.postUtteranceDelay = 0.02

        requestedAtNanoseconds = DispatchTime.now().uptimeNanoseconds
        setSpeaking(true)
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        setSpeaking(false)
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = now > requestedAtNanoseconds
            ? now - requestedAtNanoseconds
            : 0
        onSpeechStarted?(Double(elapsed) / 1_000_000)
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        setSpeaking(false)
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        setSpeaking(false)
    }

    private func setSpeaking(_ value: Bool) {
        stateLock.lock()
        speaking = value
        stateLock.unlock()
    }

    private static func preferredFeminineVoice() -> AVSpeechSynthesisVoice? {
        let englishVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }

        // Veena keeps the familiar Indian-English sound when it is installed.
        // The remaining voices are natural feminine fallbacks available on iOS.
        let preferredNames = ["Veena", "Ava", "Samantha", "Serena", "Karen"]
        for name in preferredNames {
            if let voice = englishVoices.first(where: {
                $0.name.localizedCaseInsensitiveContains(name)
            }) {
                return voice
            }
        }

        return AVSpeechSynthesisVoice(language: "en-US")
            ?? AVSpeechSynthesisVoice(language: "en-IN")
    }
}
