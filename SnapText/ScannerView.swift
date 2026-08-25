import SwiftUI

struct ScannerView: View {
    @EnvironmentObject private var store: CaptureStore
    @StateObject private var camera = CameraService()
    @Environment(\.scenePhase) private var scenePhase

    @State private var isProcessing = false
    @State private var flashOpacity = 0.0
    @State private var toast: Toast?
    @State private var showCaptures = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.status {
            case .running, .idle:
                cameraLayer
            case .denied:
                PermissionMessage(
                    icon: "camera.fill",
                    title: "Camera access needed",
                    message: "SnapText reads text through the camera. Allow camera access in Settings.",
                    showsSettingsButton: true
                )
            case .unavailable:
                PermissionMessage(
                    icon: "video.slash.fill",
                    title: "No camera available",
                    message: "This device has no usable camera. Captured texts are still available in your list.",
                    showsSettingsButton: false
                )
            }

            overlayControls
        }
        .statusBarHidden()
        .onAppear { camera.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: camera.start()
            case .background: camera.stop()
            default: break
            }
        }
        .sheet(isPresented: $showCaptures) {
            CapturesListView()
        }
    }

    // MARK: - Layers

    private var cameraLayer: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { capture() }
    }

    private var overlayControls: some View {
        VStack {
            HStack {
                if camera.status == .running && camera.position == .back {
                    ControlButton(
                        systemImage: camera.isTorchOn ? "bolt.fill" : "bolt.slash",
                        label: "Torch"
                    ) {
                        camera.toggleTorch()
                    }
                }
                Spacer()
                if camera.status == .running {
                    ControlButton(
                        systemImage: "arrow.triangle.2.circlepath.camera",
                        label: "Flip camera"
                    ) {
                        camera.flipCamera()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            if let toast {
                ToastView(toast: toast)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            bottomBar
        }
    }

    private var bottomBar: some View {
        HStack {
            Text(camera.status == .running ? "Tap anywhere to capture text" : "")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            Button {
                showCaptures = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.justify.left")
                    Text("\(store.captures.count)")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.white.opacity(0.18), in: Capsule())
            }
            .accessibilityLabel("Show \(store.captures.count) captured texts")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Capture

    private func capture() {
        guard camera.status == .running, !isProcessing else { return }
        guard let buffer = camera.latestPixelBuffer() else {
            showToast(Toast(kind: .warning, message: "Camera is still warming up"))
            return
        }

        isProcessing = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeOut(duration: 0.08)) { flashOpacity = 0.65 }
        withAnimation(.easeIn(duration: 0.25).delay(0.08)) { flashOpacity = 0 }

        Task {
            let text = await Task.detached(priority: .userInitiated) {
                try? OCRService.recognizeText(in: buffer)
            }.value

            isProcessing = false
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                showToast(Toast(kind: .warning, message: "No text found"))
            } else {
                store.add(text: trimmed)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showToast(Toast(kind: .success, message: trimmed))
            }
        }
    }

    private func showToast(_ newToast: Toast) {
        withAnimation(.spring(duration: 0.3)) { toast = newToast }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if toast?.id == newToast.id {
                withAnimation(.easeOut(duration: 0.3)) { toast = nil }
            }
        }
    }
}

// MARK: - Pieces

struct Toast: Identifiable, Equatable {
    enum Kind {
        case success
        case warning
    }

    let id = UUID()
    let kind: Kind
    let message: String
}

private struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: toast.kind == .success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(toast.kind == .success ? .green : .yellow)
            Text(toast.message)
                .font(.footnote)
                .foregroundStyle(.white)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ControlButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.45), in: Circle())
        }
        .accessibilityLabel(label)
    }
}

private struct PermissionMessage: View {
    let icon: String
    let title: String
    let message: String
    let showsSettingsButton: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.6))
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            if showsSettingsButton {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 36)
    }
}
