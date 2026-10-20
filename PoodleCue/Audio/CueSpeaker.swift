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
        utterance.voice = AVSpeechSynthesisVoice(language: "en-IN")
        utterance.rate = 0.52
        utterance.pitchMultiplier = 0.96
        utterance.volume = 0.72

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
}
