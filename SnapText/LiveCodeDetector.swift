import CoreVideo
import Foundation
import Vision

/// Runs throttled barcode detection on the camera feed. In code mode a code is
/// saved the moment it is sighted — pointing the camera is the whole gesture —
/// so sightings are deduplicated: a payload saves once and only saves again
/// after it has been out of frame for the cooldown.
final class LiveCodeDetector: ObservableObject {
    /// The code currently in frame, for the preview chip.
    @Published private(set) var liveCode: DetectedCode?

    /// Supplies the Vision region of interest for a frame; called on a camera queue.
    var regionProvider: ((CVPixelBuffer) -> CGRect?)?
    /// Called on the main thread for each code that cleared the cooldown and should be saved.
    var onCode: ((DetectedCode) -> Void)?

    private let queue = DispatchQueue(label: "SnapText.live-code", qos: .userInitiated)
    private let lock = NSLock()
    private var busy = false
    private var paused = false
    private var lastRun = Date.distantPast
    private var lastSeen: [String: Date] = [:]
    /// Barcode detection is far cheaper than OCR, so it can run near frame rate
    /// for snappy auto-capture.
    private let interval: TimeInterval = 0.15
    private let cooldown: TimeInterval = 2.0

    var isPaused: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return paused
        }
        set {
            lock.lock()
            paused = newValue
            if newValue {
                lastSeen.removeAll()
            }
            lock.unlock()
            if newValue {
                DispatchQueue.main.async { self.liveCode = nil }
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
            let codes = (try? BarcodeService.detectCodes(in: buffer, regionOfInterest: roi)) ?? []
            let fresh = self.register(codes)
            let current = codes.first

            DispatchQueue.main.async {
                if self.liveCode != current {
                    self.liveCode = current
                }
                for code in fresh {
                    self.onCode?(code)
                }
            }

            self.lock.lock()
            self.busy = false
            self.lastRun = Date()
            self.lock.unlock()
        }
    }

    /// Records sightings and returns the codes not seen within the cooldown —
    /// the ones that should be saved now. Shared by the auto path and manual taps
    /// so a tap never double-saves what auto-capture just stored.
    func register(_ codes: [DetectedCode]) -> [DetectedCode] {
        let now = Date()
        lock.lock()
        defer { lock.unlock() }
        guard !paused else { return [] }

        lastSeen = lastSeen.filter { now.timeIntervalSince($0.value) < cooldown }
        var fresh: [DetectedCode] = []
        for code in codes {
            if lastSeen[code.payload] == nil {
                fresh.append(code)
            }
            lastSeen[code.payload] = now
        }
        return fresh
    }
}
