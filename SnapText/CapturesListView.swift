import SwiftUI
import UniformTypeIdentifiers

struct CapturesListView: View {
    @EnvironmentObject private var store: CaptureStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDeleteAll = false
    @State private var showFileExporter = false
    @State private var searchText = ""

    private var filteredCaptures: [Capture] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.captures }
        return store.captures.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.captures.isEmpty {
                    ContentUnavailableView(
                        "No captures yet",
                        systemImage: "qrcode.viewfinder",
                        description: Text("Point the camera at a QR code or barcode to save it, or switch to Text mode and tap to capture text.")
                    )
                } else if filteredCaptures.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        ForEach(filteredCaptures) { capture in
                            NavigationLink(value: capture) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(capture.text)
                                        .font(.subheadline)
                                        .lineLimit(3)
                                    HStack(spacing: 6) {
                                        if capture.kind == .code {
                                            Label(capture.symbology ?? "Code", systemImage: "qrcode")
                                                .labelStyle(.titleAndIcon)
                                                .font(.caption2.weight(.medium))
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(.quaternary, in: Capsule())
                                        }
                                        Text(capture.date, format: .dateTime.month().day().hour().minute())
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    store.delete(capture)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $searchText, prompt: "Search captures")
            .navigationTitle("Captures")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Capture.self) { capture in
                CaptureDetailView(capture: capture)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !store.captures.isEmpty {
                        Menu {
                            ShareLink(item: store.combinedText) {
                                Label("Share all", systemImage: "square.and.arrow.up")
                            }
                            Button {
                                UIPasteboard.general.string = store.combinedText
                            } label: {
                                Label("Copy all", systemImage: "doc.on.doc")
                            }
                            Button {
                                showFileExporter = true
                            } label: {
                                Label("Save to Files", systemImage: "folder")
                            }
                            Button(role: .destructive) {
                                confirmDeleteAll = true
                            } label: {
                                Label("Delete all", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog(
                "Delete all captures?",
                isPresented: $confirmDeleteAll,
                titleVisibility: .visible
            ) {
                Button("Delete all", role: .destructive) { store.deleteAll() }
            }
            .fileExporter(
                isPresented: $showFileExporter,
                document: TextFileDocument(text: store.combinedText),
                contentType: .plainText,
                defaultFilename: "SnapText Captures"
            ) { _ in }
        }
    }
}

struct TextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(data: data, encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct CaptureDetailView: View {
    let capture: Capture
    @State private var copied = false

    private var linkURL: URL? {
        guard capture.kind == .code,
              let url = URL(string: capture.text),
              url.scheme == "http" || url.scheme == "https"
        else { return nil }
        return url
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if capture.kind == .code {
                    Label(capture.symbology ?? "Code", systemImage: "qrcode")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
                Text(capture.text)
                    .font(capture.kind == .code ? .body.monospaced() : .body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let linkURL {
                    Link(destination: linkURL) {
                        Label("Open Link", systemImage: "safari")
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle(capture.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: capture.text)
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    UIPasteboard.general.string = capture.text
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy text", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
