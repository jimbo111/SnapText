import CoreVideo
import SwiftUI

/// Thread-safe snapshot of the capture region, readable from camera queues.
final class CropState {
    private let lock = NSLock()
    private var rect: CGRect?
    private var viewSize: CGSize = .zero
    private var mirrored = false

    func update(rect: CGRect?, viewSize: CGSize, mirrored: Bool) {
        lock.lock()
        self.rect = rect
        self.viewSize = viewSize
        self.mirrored = mirrored
        lock.unlock()
    }

    /// Maps the on-screen crop rectangle (drawn over an aspect-fill preview)
    /// to a Vision region of interest: normalized, origin at bottom-left.
    func visionROI(for buffer: CVPixelBuffer) -> CGRect? {
        lock.lock()
        let rect = self.rect
        let viewSize = self.viewSize
        let mirrored = self.mirrored
        lock.unlock()

        guard let rect, viewSize.width > 0, viewSize.height > 0 else { return nil }
        let bufferWidth = CGFloat(CVPixelBufferGetWidth(buffer))
        let bufferHeight = CGFloat(CVPixelBufferGetHeight(buffer))
        guard bufferWidth > 0, bufferHeight > 0 else { return nil }

        // Aspect-fill: the buffer is scaled up until it covers the view, then centered.
        let scale = max(viewSize.width / bufferWidth, viewSize.height / bufferHeight)
        let offsetX = (bufferWidth * scale - viewSize.width) / 2
        let offsetY = (bufferHeight * scale - viewSize.height) / 2

        var x = (rect.minX + offsetX) / scale / bufferWidth
        let width = rect.width / scale / bufferWidth
        let height = rect.height / scale / bufferHeight
        let topY = (rect.minY + offsetY) / scale / bufferHeight
        // The front-camera preview is mirrored but its buffers are not.
        if mirrored {
            x = 1 - x - width
        }
        let y = 1 - topY - height

        let roi = CGRect(x: x, y: y, width: width, height: height)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        return roi.isEmpty ? nil : roi
    }
}

/// Draggable, resizable capture frame. Tapping inside it still captures.
struct CropBoxOverlay: View {
    @Binding var rect: CGRect
    let containerSize: CGSize
    let onTap: () -> Void

    @State private var moveStart: CGRect?
    @State private var resizeStart: CGRect?

    private static let minSize = CGSize(width: 100, height: 80)
    private static let inset: CGFloat = 12
    private static let cornerRadius: CGFloat = 12

    private enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    var body: some View {
        ZStack {
            dimming
            boxBorder
            ForEach(Corner.allCases, id: \.self) { corner in
                handle(for: corner)
            }
        }
    }

    private var dimming: some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: containerSize))
            path.addRoundedRect(
                in: rect,
                cornerSize: CGSize(width: Self.cornerRadius, height: Self.cornerRadius)
            )
        }
        .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    private var boxBorder: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius)
            .stroke(.white, lineWidth: 1.5)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            .onTapGesture { onTap() }
            .gesture(moveGesture)
    }

    private func handle(for corner: Corner) -> some View {
        Circle()
            .fill(.white)
            .frame(width: 14, height: 14)
            .padding(14)
            .contentShape(Circle())
            .position(position(of: corner))
            .gesture(resizeGesture(for: corner))
    }

    // MARK: - Gestures

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if moveStart == nil { moveStart = rect }
                guard var moved = moveStart else { return }
                moved.origin.x += value.translation.width
                moved.origin.y += value.translation.height
                rect = clampedPosition(moved)
            }
            .onEnded { _ in moveStart = nil }
    }

    private func resizeGesture(for corner: Corner) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if resizeStart == nil { resizeStart = rect }
                guard let start = resizeStart else { return }
                rect = resized(start, corner: corner, by: value.translation)
            }
            .onEnded { _ in resizeStart = nil }
    }

    // MARK: - Geometry

    private func position(of corner: Corner) -> CGPoint {
        switch corner {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private func clampedPosition(_ r: CGRect) -> CGRect {
        var r = r
        r.origin.x = min(max(Self.inset, r.origin.x), containerSize.width - Self.inset - r.width)
        r.origin.y = min(max(Self.inset, r.origin.y), containerSize.height - Self.inset - r.height)
        return r
    }

    private func resized(_ start: CGRect, corner: Corner, by translation: CGSize) -> CGRect {
        var minX = start.minX
        var minY = start.minY
        var maxX = start.maxX
        var maxY = start.maxY

        switch corner {
        case .topLeft:
            minX += translation.width
            minY += translation.height
        case .topRight:
            maxX += translation.width
            minY += translation.height
        case .bottomLeft:
            minX += translation.width
            maxY += translation.height
        case .bottomRight:
            maxX += translation.width
            maxY += translation.height
        }

        minX = max(Self.inset, minX)
        minY = max(Self.inset, minY)
        maxX = min(containerSize.width - Self.inset, maxX)
        maxY = min(containerSize.height - Self.inset, maxY)

        switch corner {
        case .topLeft:
            minX = min(minX, maxX - Self.minSize.width)
            minY = min(minY, maxY - Self.minSize.height)
        case .topRight:
            maxX = max(maxX, minX + Self.minSize.width)
            minY = min(minY, maxY - Self.minSize.height)
        case .bottomLeft:
            minX = min(minX, maxX - Self.minSize.width)
            maxY = max(maxY, minY + Self.minSize.height)
        case .bottomRight:
            maxX = max(maxX, minX + Self.minSize.width)
            maxY = max(maxY, minY + Self.minSize.height)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
