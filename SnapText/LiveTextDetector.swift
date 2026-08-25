import CoreVideo
import Foundation

/// Runs throttled fast OCR on the camera feed so the UI can show what a tap
/// would capture. Saved captures use the accurate path in ScannerView instead.
final class LiveTextDetector: ObservableObject {
    @Published private(set) var snippet: String?

    /// Supplies the Vision region of interest for a frame; called on a camera queue.
    var regionProvider: ((CVPixelBuffer) -> CGRect?)?

    private let queue = DispatchQueue(label: "SnapText.live-ocr", qos: .utility)
    private let lock = NSLock()
    private var busy = false
    private var paused = false
    private var lastRun = Date.distantPast
    private let interval: TimeInterval = 0.4

    var isPaused: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return paused
        }
        set {
            lock.lock()
            paused = newValue
            lock.unlock()
            if newValue {
                DispatchQueue.main.async { self.snippet = nil }
            }
        }
    }

    /// Called on the camera frame queue with every new frame.
    func process(_ buffer: CVPixelBuffer) {
        lock.lock()
        guard !busy, !paused, Date().timeIntervalSince(lastRun) >= interval else {
            lock.unlock()
            return
        }
        busy = true
        lock.unlock()

        let roi = regionProvider?(buffer)
        queue.async { [weak self] in
            guard let self else { return }
            let text = (try? OCRService.recognizeText(in: buffer, regionOfInterest: roi, fast: true)) ?? ""
            let firstLine = text.split(separator: "\n").first.map(String.init)

            DispatchQueue.main.async {
                if self.snippet != firstLine {
                    self.snippet = firstLine
                }
            }

            self.lock.lock()
            self.busy = false
            self.lastRun = Date()
            self.lock.unlock()
        }
    }
}
