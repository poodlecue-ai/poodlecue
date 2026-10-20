import Foundation

enum ConversationCueIntent: String, Equatable {
    case empathy = "Empathy"
    case answer = "Answer"
    case followUp = "Follow-up"
    case recall = "Recall"
    case celebrate = "Celebrate"
}

struct LocalConversationCue: Equatable {
    let text: String
    let reason: String
    let intent: ConversationCueIntent
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
        memorySummary: String? = nil,
        previousUserTurn: String? = nil,
        recentCueTexts: [String] = []
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
        guard let selection = selectCue(
            for: segment.lowercased(),
            memorySummary: memorySummary?.lowercased(),
            previousUserTurn: previousUserTurn?.lowercased()
        ) else {
            lastTranscript = transcript
            return nil
        }
        let finishedAt = DispatchTime.now().uptimeNanoseconds

        guard
            selection.text != lastCue,
            !recentCueTexts.suffix(3).contains(selection.text)
        else {
            lastTranscript = transcript
            return nil
        }

        lastTranscript = transcript
        lastCue = selection.text
        lastIssuedAtNanoseconds = now

        return LocalConversationCue(
            text: selection.text,
            reason: selection.reason,
            intent: selection.intent,
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
            intent: .recall,
            generationMilliseconds: Double(
                DispatchTime.now().uptimeNanoseconds - startedAt
            ) / 1_000_000
        )
    }

    private func selectCue(
        for text: String,
        memorySummary: String?,
        previousUserTurn: String?
    ) -> (text: String, reason: String, intent: ConversationCueIntent)? {
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        guard wordCount >= 3 else { return nil }

        if containsAny(text, [
            "didn't sleep", "didn’t sleep", "did not sleep", "not well", "unwell", "sick",
            "difficult", "hard time", "stressed", "worried", "bad day", "tired"
        ]) {
            if containsAny(text, ["kid", "child", "daughter", "son", "family"]) {
                return (
                    "Ask if everyone is doing okay today.",
                    "Responds with empathy to a family difficulty",
                    .empathy
                )
            }
            return (
                "Acknowledge that, then ask how they’re doing.",
                "Responds with empathy to a difficult experience",
                .empathy
            )
        }

        if containsAny(text, ["excited", "great news", "good news", "proud", "happy", "amazing"]) {
            return (
                "Celebrate that, then ask what happens next.",
                "Responds to positive emotion",
                .celebrate
            )
        }

        if containsAny(text, ["what do you", "how do you", "where do you", "have you", "did you", "are you", "can you"]) {
            return (
                "Answer simply, then ask them back.",
                "Detected a question directed at you",
                .answer
            )
        }

        if let memorySummary, sharesTopic(text, memorySummary) {
            return (
                "Ask what’s changed since last time.",
                "Connected this detail to your saved memory",
                .recall
            )
        }

        if containsAny(text, ["gym", "workout", "training", "exercise", "running", "run "]) {
            guard !alreadyAsked(about: ["train", "workout", "run", "marathon"], in: previousUserTurn) else {
                return nil
            }
            return ("Ask what they’re training for.", "Picked up a fitness detail", .followUp)
        }

        if containsAny(text, ["work", "job", "office", "company", "career", "study", "college"]) {
            guard !alreadyAsked(about: ["work", "job", "office", "study", "college"], in: previousUserTurn) else {
                return nil
            }
            return ("Ask what they like about it.", "Picked up a work or study detail", .followUp)
        }

        if containsAny(text, ["travel", "trip", "visited", "from ", "moved", "city", "country"]) {
            guard !alreadyAsked(about: ["travel", "trip", "place", "where"], in: previousUserTurn) else {
                return nil
            }
            return ("Ask what brought them there.", "Picked up a place or travel detail", .followUp)
        }

        if containsAny(text, ["weekend", "holiday", "tomorrow", "next week", "plan "]) {
            return ("Ask what they’re looking forward to.", "Picked up a future plan", .followUp)
        }

        if containsAny(text, ["friend", "family", "brother", "sister", "partner", "colleague"]) {
            return ("Ask a little more about that person.", "Picked up a relationship detail", .followUp)
        }

        // The policy deliberately stays silent for short acknowledgements and
        // low-signal statements instead of producing a generic cue every time.
        guard wordCount >= 8 else { return nil }
        return ("Ask about the detail that seemed most important.", "Offers a general follow-up", .followUp)
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

    private func alreadyAsked(about terms: [String], in previousTurn: String?) -> Bool {
        guard let previousTurn else { return false }
        let looksLikeQuestion = previousTurn.contains("?") || containsAny(
            previousTurn,
            ["what", "why", "how", "where", "when", "which", "do you", "are you"]
        )
        return looksLikeQuestion && containsAny(previousTurn, terms)
    }
}
