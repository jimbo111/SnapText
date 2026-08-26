import Foundation

struct Capture: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let date: Date
}

/// Saved captures, newest first, persisted as JSON in the app's Documents directory.
@MainActor
final class CaptureStore: ObservableObject {
    @Published private(set) var captures: [Capture] = []

    private let fileURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("captures.json")
        load()
    }

    func add(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        captures.insert(Capture(id: UUID(), text: trimmed, date: Date()), at: 0)
        save()
    }

    func delete(_ capture: Capture) {
        captures.removeAll { $0.id == capture.id }
        save()
    }

    func deleteAll() {
        captures.removeAll()
        save()
    }

    /// All captures joined into one document, oldest first (capture order).
    var combinedText: String {
        captures.reversed().map(\.text).joined(separator: "\n\n")
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            captures = try JSONDecoder().decode([Capture].self, from: data)
        } catch {
            // Keep the unreadable file for manual recovery; otherwise the next
            // save would silently overwrite it and lose every past capture.
            let backupURL = fileURL.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.moveItem(at: fileURL, to: backupURL)
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(captures)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Disk-full or similar; captures stay available in memory for this session.
        }
    }
}
