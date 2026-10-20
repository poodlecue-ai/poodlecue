import Foundation

struct ConversationMemory: Codable, Identifiable, Equatable {
    let id: UUID
    var personName: String
    var summary: String
    var lastMetAt: Date
}

@MainActor
final class ConversationMemoryStore: ObservableObject {
    @Published private(set) var memories: [ConversationMemory] = []

    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let supportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let directory = supportDirectory.appendingPathComponent("PoodleCue", isDirectory: true)
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        fileURL = directory.appendingPathComponent("conversation-memories.json")
        load()
    }

    @discardableResult
    func save(personName: String, summary: String) -> ConversationMemory? {
        let name = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !note.isEmpty else { return nil }

        let memory: ConversationMemory
        if let index = memories.firstIndex(where: {
            $0.personName.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            memories[index].personName = name
            memories[index].summary = note
            memories[index].lastMetAt = Date()
            memory = memories[index]
        } else {
            memory = ConversationMemory(
                id: UUID(),
                personName: name,
                summary: note,
                lastMetAt: Date()
            )
            memories.append(memory)
        }

        memories.sort { $0.lastMetAt > $1.lastMetAt }
        persist()
        return memory
    }

    func delete(_ memory: ConversationMemory) {
        memories.removeAll { $0.id == memory.id }
        persist()
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: fileURL),
            let stored = try? JSONDecoder().decode([ConversationMemory].self, from: data)
        else { return }
        memories = stored.sorted { $0.lastMetAt > $1.lastMetAt }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(memories)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            assertionFailure("Could not save conversation memories: \(error)")
        }
    }
}

enum MemorySummaryBuilder {
    static func draft(from transcript: String) -> String {
        let normalized = transcript
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return "" }
        let maximumLength = 180
        guard normalized.count > maximumLength else { return normalized }

        let boundary = normalized.index(normalized.startIndex, offsetBy: maximumLength)
        return String(normalized[..<boundary]).trimmingCharacters(in: .whitespaces) + "…"
    }
}
