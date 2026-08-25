import SwiftUI

struct CapturesListView: View {
    @EnvironmentObject private var store: CaptureStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDeleteAll = false

    var body: some View {
        NavigationStack {
            Group {
                if store.captures.isEmpty {
                    ContentUnavailableView(
                        "No captures yet",
                        systemImage: "text.viewfinder",
                        description: Text("Point the camera at any text and tap the screen to save it.")
                    )
                } else {
                    List {
                        ForEach(store.captures) { capture in
                            NavigationLink(value: capture) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(capture.text)
                                        .font(.subheadline)
                                        .lineLimit(3)
                                    Text(capture.date, format: .dateTime.month().day().hour().minute())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .onDelete { store.delete(at: $0) }
                    }
                    .listStyle(.plain)
                }
            }
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
        }
    }
}

private struct CaptureDetailView: View {
    let capture: Capture
    @State private var copied = false

    var body: some View {
        ScrollView {
            Text(capture.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
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
