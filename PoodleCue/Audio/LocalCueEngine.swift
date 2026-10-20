import Foundation

struct LocalConversationCue: Equatable {
    let text: String
    let reason: String
    let generationMilliseconds: Double
}

final class LocalCueEngine {
    // Cues are already gated by end-of-turn speech detection. Keep only a
    // short debounce so a natural, quick reply is not silently discarded.
    private let minimumIntervalNanoseconds: UInt64 = 750_000_000
    private var lastIssuedAtNanoseconds: UInt64 = 0
    private var lastTranscript = ""
    private var lastCue = ""

    func suggest(
        from fullTranscript: String,
        memorySummary: String? = nil
    ) -> LocalConversationCue? {
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
        let selection = selectCue(
            for: segment.lowercased(),
            memorySummary: memorySummary?.lowercased()
        )
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

    func beginTurn(at fullTranscript: String) {
        lastTranscript = fullTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func followUpCue(personName: String, summary: String) -> LocalConversationCue {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let text = summary.lowercased()
        let cue: String

        if containsAny(text, ["gym", "workout", "training", "exercise", "running", "marathon"]) {
            cue = "Ask \(personName) how their training is going."
        } else if containsAny(text, ["kid", "child", "daughter", "son", "family", "sleep"]) {
            cue = "Ask \(personName) how things are with the family."
        } else if containsAny(text, ["work", "job", "office", "company", "career", "study", "college"]) {
            cue = "Ask \(personName) how work or study has been."
        } else if containsAny(text, ["travel", "trip", "visited", "holiday", "city", "country"]) {
            cue = "Ask \(personName) how the trip or travel plan went."
        } else {
            cue = "Ask \(personName) what’s changed since you last spoke."
        }

        return LocalConversationCue(
            text: cue,
            reason: "Based on your saved memory",
            generationMilliseconds: Double(
                DispatchTime.now().uptimeNanoseconds - startedAt
            ) / 1_000_000
        )
    }

    private func selectCue(
        for text: String,
        memorySummary: String?
    ) -> (text: String, reason: String) {
        if let memorySummary, sharesTopic(text, memorySummary) {
            return (
                "Ask what’s changed since last time.",
                "Connected this detail to your saved memory"
            )
        }

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

    private func sharesTopic(_ text: String, _ memory: String) -> Bool {
        let topicGroups = [
            ["gym", "workout", "training", "exercise", "running", "marathon"],
            ["kid", "child", "daughter", "son", "family", "sleep"],
            ["work", "job", "office", "company", "career", "study", "college"],
            ["travel", "trip", "visited", "holiday", "city", "country"]
        ]
        return topicGroups.contains { group in
            containsAny(text, group) && containsAny(memory, group)
        }
    }
}
