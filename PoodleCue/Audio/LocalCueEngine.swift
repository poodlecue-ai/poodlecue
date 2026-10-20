import Foundation

struct LocalConversationCue: Equatable {
    let text: String
    let reason: String
    let generationMilliseconds: Double
}

final class LocalCueEngine {
    private let minimumIntervalNanoseconds: UInt64 = 4_000_000_000
    private var lastIssuedAtNanoseconds: UInt64 = 0
    private var lastTranscript = ""
    private var lastCue = ""

    func suggest(from fullTranscript: String) -> LocalConversationCue? {
        let transcript = fullTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return nil }

        let now = DispatchTime.now().uptimeNanoseconds
        guard
            lastIssuedAtNanoseconds == 0 ||
            now - lastIssuedAtNanoseconds >= minimumIntervalNanoseconds
        else { return nil }

        let newSegment: String
        if transcript.hasPrefix(lastTranscript) {
            newSegment = String(transcript.dropFirst(lastTranscript.count))
        } else {
            newSegment = transcript
        }

        let segment = newSegment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard segment.split(whereSeparator: \.isWhitespace).count >= 3 else {
            return nil
        }

        let startedAt = DispatchTime.now().uptimeNanoseconds
        let selection = selectCue(for: segment.lowercased())
        let finishedAt = DispatchTime.now().uptimeNanoseconds

        guard selection.text != lastCue else {
            lastTranscript = transcript
            return nil
        }

        lastTranscript = transcript
        lastCue = selection.text
        lastIssuedAtNanoseconds = now

        return LocalConversationCue(
            text: selection.text,
            reason: selection.reason,
            generationMilliseconds: Double(finishedAt - startedAt) / 1_000_000
        )
    }

    func reset() {
        lastIssuedAtNanoseconds = 0
        lastTranscript = ""
        lastCue = ""
    }

    private func selectCue(for text: String) -> (text: String, reason: String) {
        if containsAny(text, ["gym", "workout", "training", "exercise", "running", "run "]) {
            return ("Ask what they’re training for.", "Picked up a fitness detail")
        }

        if containsAny(text, ["work", "job", "office", "company", "career", "study", "college"]) {
            return ("Ask what they like about it.", "Picked up a work or study detail")
        }

        if containsAny(text, ["travel", "trip", "visited", "from ", "moved", "city", "country"]) {
            return ("Ask what brought them there.", "Picked up a place or travel detail")
        }

        if containsAny(text, ["weekend", "holiday", "tomorrow", "next week", "plan "]) {
            return ("Ask what they’re looking forward to.", "Picked up a future plan")
        }

        if containsAny(text, ["friend", "family", "brother", "sister", "partner", "colleague"]) {
            return ("Ask how they know each other.", "Picked up a relationship detail")
        }

        if containsAny(text, ["what do you", "how do you", "where do you", "have you", "did you"]) {
            return ("Answer simply, then ask them back.", "Detected a question")
        }

        return ("Ask about that last detail.", "Keeps the conversation moving")
    }

    private func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }
}
