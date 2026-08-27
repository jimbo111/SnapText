import Foundation

struct Capture: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case text
        case code
    }

    let id: UUID
    let text: String
    let date: Date
    let kind: Kind
    /// Human-readable symbology ("QR", "EAN-13", …) for code captures.
    let symbology: String?

    init(id: UUID, text: String, date: Date, kind: Kind = .text, symbology: String? = nil) {
        self.id = id
        self.text = text
        self.date = date
        self.kind = kind
        self.symbology = symbology
    }

    init(from decoder: Decoder) throws {
        // Captures saved before code scanning existed have no kind/symbology.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        date = try container.decode(Date.self, forKey: .date)
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .text
        symbology = try container.decodeIfPresent(String.self, forKey: .symbology)
    }
}

/// Saved captures, newest first, persisted as JSON in the app's Documents directory.
@MainActor
final class CaptureStore: ObservableObject {
    @Published private(set) var captures: [Capture] = []

    private let fileURL: URL
    /// Serial, so writes land in order; keeps JSON encoding and disk I/O off the
    /// main thread during rapid-fire capture bursts.
    private let saveQueue = DispatchQueue(label: "SnapText.store.save", qos: .utility)

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("captures.json")
        load()
    }

    func add(text: String, kind: Capture.Kind = .text, symbology: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        captures.insert(
            Capture(id: UUID(), text: trimmed, date: Date(), kind: kind, symbology: symbology),
            at: 0
        )
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
        let snapshot = captures
        saveQueue.async { [fileURL = fileURL] in
            // Disk-full or similar; captures stay available in memory for this session.
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
