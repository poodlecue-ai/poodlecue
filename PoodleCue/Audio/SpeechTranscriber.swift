import AVFoundation
import Speech

final class SpeechTranscriber {
    enum TranscriptionError: LocalizedError {
        case permissionRequired
        case onDeviceRecognitionUnavailable

        var errorDescription: String? {
            switch self {
            case .permissionRequired:
                return "Speech recognition permission is required for live transcription."
            case .onDeviceRecognitionUnavailable:
                return "On-device speech recognition is unavailable for the current language. PoodleCue will not send audio to a network service."
            }
        }
    }

    typealias TranscriptHandler = (_ text: String, _ isFinal: Bool) -> Void

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isRunning = false
    private var lastTranscript = ""

    var onTranscript: TranscriptHandler?
    var onError: ((String) -> Void)?

    func start() throws -> String {
        stop()

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw TranscriptionError.permissionRequired
        }

        guard let recognizer = makeOnDeviceRecognizer() else {
            throw TranscriptionError.onDeviceRecognitionUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation

        self.recognizer = recognizer
        self.request = request
        isRunning = true
        lastTranscript = ""

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self, self.isRunning else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                if text != self.lastTranscript {
                    self.lastTranscript = text
                    self.onTranscript?(text, result.isFinal)
                }
            }

            if let error {
                self.isRunning = false
                self.onError?("On-device transcription stopped: \(error.localizedDescription)")
            }
        }

        return recognizer.locale.identifier
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard isRunning else { return }
        request?.append(buffer)
    }

    func stop() {
        isRunning = false
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
        lastTranscript = ""
    }

    private func makeOnDeviceRecognizer() -> SFSpeechRecognizer? {
        var identifiers = [Locale.current.identifier, "en-IN", "en-US"]
        var seen = Set<String>()
        identifiers = identifiers.filter { seen.insert($0).inserted }

        for identifier in identifiers {
            guard let recognizer = SFSpeechRecognizer(
                locale: Locale(identifier: identifier)
            ) else { continue }

            if recognizer.isAvailable && recognizer.supportsOnDeviceRecognition {
                return recognizer
            }
        }

        return nil
    }
}
