import SwiftUI
import Vision

enum ScanMode: String {
    case text
    case code
}

struct ScannerView: View {
    @EnvironmentObject private var store: CaptureStore
    @StateObject private var camera = CameraService()
    @StateObject private var liveText = LiveTextDetector()
    @StateObject private var liveCode = LiveCodeDetector()
    @State private var cropState = CropState()
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("scanMode") private var scanMode: ScanMode = .code

    @State private var viewSize: CGSize = .zero
    @State private var cropEnabled = false
    @State private var cropRect: CGRect?

    @State private var isProcessing = false
    @State private var flashOpacity = 0.0
    @State private var toast: Toast?
    @State private var showCaptures = false
    @State private var zoomGestureBase: CGFloat?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.status {
            case .running, .idle:
                cameraArea
            case .denied:
                PermissionMessage(
                    icon: "camera.fill",
                    title: "Camera access needed",
                    message: "SnapText scans codes and text through the camera. Allow camera access in Settings.",
                    showsSettingsButton: true
                )
            case .unavailable:
                PermissionMessage(
                    icon: "video.slash.fill",
                    title: "No camera available",
                    message: "This device has no usable camera. Saved captures are still available in your list.",
                    showsSettingsButton: false
                )
            }

            overlayControls
        }
        .statusBarHidden()
        .onAppear {
            camera.frameHandler = { [weak liveText, weak liveCode] buffer in
                liveText?.process(buffer)
                liveCode?.process(buffer)
            }
            liveText.regionProvider = { [cropState] buffer in
                cropState.visionROI(for: buffer)
            }
            liveCode.regionProvider = { [cropState] buffer in
                cropState.visionROI(for: buffer)
            }
            liveCode.onCode = { code in
                saveCode(code)
            }
            syncDetectorPauses()
            camera.start()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: camera.start()
            case .background: camera.stop()
            default: break
            }
        }
        .onChange(of: cropEnabled) { _, _ in syncCrop() }
        .onChange(of: cropRect) { _, _ in syncCrop() }
        .onChange(of: camera.position) { _, _ in syncCrop() }
        .onChange(of: showCaptures) { _, _ in syncDetectorPauses() }
        .onChange(of: scanMode) { _, _ in syncDetectorPauses() }
        .sheet(isPresented: $showCaptures) {
            CapturesListView()
        }
    }

    // MARK: - Layers

    private var cameraArea: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreview(session: camera.session)

                Color.white
                    .opacity(flashOpacity)
                    .allowsHitTesting(false)

                if cropEnabled {
                    CropBoxOverlay(rect: cropBinding, containerSize: geo.size, onTap: capture)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { capture() }
            .simultaneousGesture(zoomGesture)
            .onChange(of: geo.size, initial: true) { _, size in
                viewSize = size
                if let rect = cropRect {
                    cropRect = Self.clampedToContainer(rect, in: size)
                }
                syncCrop()
            }
        }
        .ignoresSafeArea()
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if zoomGestureBase == nil { zoomGestureBase = camera.zoomFactor }
                camera.setZoomFactor((zoomGestureBase ?? 1) * value.magnification)
            }
            .onEnded { _ in zoomGestureBase = nil }
    }

    private var overlayControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
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
                        systemImage: cropEnabled ? "viewfinder.rectangular" : "viewfinder",
                        label: cropEnabled ? "Capture full frame" : "Capture a region",
                        isActive: cropEnabled
                    ) {
                        toggleCrop()
                    }
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

            if camera.status == .running, camera.zoomFactor > 1.05 {
                Text(String(format: "%.1f×", camera.zoomFactor))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.top, 10)
                    .allowsHitTesting(false)
            }

            if let (icon, snippet) = livePreviewChip, !isProcessing {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                    Text(snippet)
                        .font(.caption)
                        .lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(.top, 10)
                .padding(.horizontal, 40)
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            Spacer()

            if let toast {
                ToastView(toast: toast)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            if camera.status == .running {
                ScanModePicker(mode: $scanMode)
                    .padding(.bottom, 12)
            }

            bottomBar
        }
        .animation(.easeInOut(duration: 0.15), value: liveText.snippet)
        .animation(.easeInOut(duration: 0.15), value: liveCode.liveCode)
    }

    private var livePreviewChip: (icon: String, snippet: String)? {
        guard camera.status == .running else { return nil }
        switch scanMode {
        case .text:
            guard let snippet = liveText.snippet else { return nil }
            return ("text.viewfinder", snippet)
        case .code:
            guard let code = liveCode.liveCode else { return nil }
            return ("qrcode.viewfinder", "\(code.symbology.displayName) · \(code.payload)")
        }
    }

    private var bottomBar: some View {
        HStack {
            Text(hintText)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .allowsHitTesting(false)

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
            .accessibilityLabel("Show \(store.captures.count) saved captures")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var hintText: String {
        guard camera.status == .running else { return "" }
        switch scanMode {
        case .text:
            return cropEnabled ? "Frame the text, then tap to capture" : "Tap anywhere to capture text"
        case .code:
            return cropEnabled ? "Frame a code — it saves itself" : "Point at a code — it saves itself"
        }
    }

    // MARK: - Crop region

    private var cropBinding: Binding<CGRect> {
        Binding(
            get: { cropRect ?? Self.defaultCropRect(in: viewSize) },
            set: { cropRect = $0 }
        )
    }

    private static func clampedToContainer(_ rect: CGRect, in size: CGSize) -> CGRect {
        guard size.width > 48, size.height > 48 else { return rect }
        var r = rect
        r.size.width = min(r.width, size.width - 24)
        r.size.height = min(r.height, size.height - 24)
        r.origin.x = min(max(12, r.origin.x), size.width - 12 - r.width)
        r.origin.y = min(max(12, r.origin.y), size.height - 12 - r.height)
        return r
    }

    private static func defaultCropRect(in size: CGSize) -> CGRect {
        guard size.width > 100, size.height > 200 else {
            return CGRect(x: 24, y: 200, width: 250, height: 180)
        }
        let width = size.width - 48
        let height = size.height * 0.3
        return CGRect(x: 24, y: (size.height - height) / 2, width: width, height: height)
    }

    private func toggleCrop() {
        if !cropEnabled && cropRect == nil {
            cropRect = Self.defaultCropRect(in: viewSize)
        }
        cropEnabled.toggle()
    }

    private func syncCrop() {
        cropState.update(
            rect: cropEnabled ? cropBinding.wrappedValue : nil,
            viewSize: viewSize,
            mirrored: camera.position == .front
        )
    }

    private func syncDetectorPauses() {
        liveText.isPaused = showCaptures || scanMode != .text
        liveCode.isPaused = showCaptures || scanMode != .code
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

        let roi = cropState.visionROI(for: buffer)
        switch scanMode {
        case .text: captureText(from: buffer, roi: roi)
        case .code: captureCodes(from: buffer, roi: roi)
        }
    }

    private func captureText(from buffer: CVPixelBuffer, roi: CGRect?) {
        Task {
            let text = await Task.detached(priority: .userInitiated) {
                try? OCRService.recognizeText(in: buffer, regionOfInterest: roi)
            }.value

            isProcessing = false
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                showToast(Toast(kind: .warning, message: cropEnabled ? "No text found in the frame" : "No text found"))
            } else {
                store.add(text: trimmed)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showToast(Toast(kind: .success, message: trimmed))
            }
        }
    }

    private func captureCodes(from buffer: CVPixelBuffer, roi: CGRect?) {
        Task {
            let codes = await Task.detached(priority: .userInitiated) {
                (try? BarcodeService.detectCodes(in: buffer, regionOfInterest: roi)) ?? []
            }.value

            isProcessing = false
            if codes.isEmpty {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                showToast(Toast(kind: .warning, message: cropEnabled ? "No code found in the frame" : "No code found"))
                return
            }
            // Route through the live detector's dedupe so a tap never double-saves
            // what auto-capture just stored.
            let fresh = liveCode.register(codes)
            if fresh.isEmpty {
                showToast(Toast(kind: .success, message: "Already saved"))
            } else {
                for code in fresh {
                    saveCode(code)
                }
            }
        }
    }

    private func saveCode(_ code: DetectedCode) {
        store.add(text: code.payload, kind: .code, symbology: code.symbology.displayName)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showToast(Toast(kind: .success, message: "\(code.symbology.displayName) · \(code.payload)"))
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

private struct ScanModePicker: View {
    @Binding var mode: ScanMode

    var body: some View {
        HStack(spacing: 4) {
            segment("Code", icon: "qrcode.viewfinder", value: .code)
            segment("Text", icon: "text.viewfinder", value: .text)
        }
        .padding(4)
        .background(.black.opacity(0.55), in: Capsule())
    }

    private func segment(_ title: String, icon: String, value: ScanMode) -> some View {
        Button {
            mode = value
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title)
                    .fontWeight(.semibold)
            }
            .font(.footnote)
            .foregroundStyle(mode == value ? .black : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(mode == value ? AnyShapeStyle(.white) : AnyShapeStyle(.clear), in: Capsule())
        }
        .accessibilityLabel("Scan \(title.lowercased())")
        .accessibilityAddTraits(mode == value ? .isSelected : [])
    }
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
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isActive ? .black : .white)
                .frame(width: 44, height: 44)
                .background(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.black.opacity(0.45)), in: Circle())
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
