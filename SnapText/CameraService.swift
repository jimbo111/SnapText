import AVFoundation
import Combine

/// Owns the capture session. Keeps the most recent video frame so a tap can be
/// turned into text with zero photo-capture latency.
final class CameraService: NSObject, ObservableObject {
    enum Status {
        case idle
        case running
        case denied
        case unavailable
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var position: AVCaptureDevice.Position = .back
    @Published private(set) var isTorchOn = false
    @Published private(set) var zoomFactor: CGFloat = 1

    let session = AVCaptureSession()

    /// Called on the frame queue with every new frame.
    var frameHandler: ((CVPixelBuffer) -> Void)? {
        get {
            frameLock.lock()
            defer { frameLock.unlock() }
            return _frameHandler
        }
        set {
            frameLock.lock()
            _frameHandler = newValue
            frameLock.unlock()
        }
    }

    private let sessionQueue = DispatchQueue(label: "SnapText.camera.session")
    private let frameQueue = DispatchQueue(label: "SnapText.camera.frames")
    private let output = AVCaptureVideoDataOutput()
    private let frameLock = NSLock()
    private var latestFrame: CVPixelBuffer?
    private var _frameHandler: ((CVPixelBuffer) -> Void)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureAndRun()
                    } else {
                        self?.status = .denied
                    }
                }
            }
        default:
            status = .denied
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.stopRunning()
            // stopRunning() physically turns the torch off.
            DispatchQueue.main.async { self.isTorchOn = false }
        }
    }

    func flipCamera() {
        let newPosition: AVCaptureDevice.Position = position == .back ? .front : .back
        sessionQueue.async { [weak self] in
            guard let self, self.replaceInput(position: newPosition) else { return }
            DispatchQueue.main.async {
                self.position = newPosition
                self.isTorchOn = false
                self.zoomFactor = 1
            }
        }
    }

    func setZoomFactor(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentDevice() else { return }
            let clamped = max(1, min(factor, min(device.activeFormat.videoMaxZoomFactor, 10)))
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.zoomFactor = clamped }
            } catch {
                // Zoom is a convenience; ignore configuration failures.
            }
        }
    }

    func toggleTorch() {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentDevice(), device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                let newMode: AVCaptureDevice.TorchMode = device.torchMode == .on ? .off : .on
                device.torchMode = newMode
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.isTorchOn = newMode == .on }
            } catch {
                // Torch is a convenience; ignore configuration failures.
            }
        }
    }

    /// The most recent camera frame, or nil if the session has not produced one yet.
    func latestPixelBuffer() -> CVPixelBuffer? {
        frameLock.lock()
        defer { frameLock.unlock() }
        return latestFrame
    }

    // MARK: - Session configuration (sessionQueue only)

    private func configureAndRun() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.inputs.isEmpty {
                self.session.beginConfiguration()
                self.session.sessionPreset = .high
                guard self.addInput(position: .back), self.addOutput() else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.status = .unavailable }
                    return
                }
                self.session.commitConfiguration()
            }
            self.session.startRunning()
            DispatchQueue.main.async { self.status = .running }
        }
    }

    private func addInput(position: AVCaptureDevice.Position) -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return false }
        session.addInput(input)
        return true
    }

    private func addOutput() -> Bool {
        // The sensor's native biplanar YCbCr format: Vision consumes it directly,
        // and requesting BGRA here would force a color conversion on every frame.
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: frameQueue)
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        applyPortraitRotation()
        return true
    }

    private func replaceInput(position: AVCaptureDevice.Position) -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        let previousInputs = session.inputs
        for input in previousInputs {
            session.removeInput(input)
        }
        guard addInput(position: position) else {
            // Put the working camera back rather than leaving the session with no input.
            for input in previousInputs where session.canAddInput(input) {
                session.addInput(input)
            }
            applyPortraitRotation()
            return false
        }
        applyPortraitRotation()
        clearLatestFrame()
        return true
    }

    private func applyPortraitRotation() {
        // Deliver upright buffers so Vision reads text in its natural orientation.
        if let connection = output.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    private func currentDevice() -> AVCaptureDevice? {
        session.inputs
            .compactMap { ($0 as? AVCaptureDeviceInput)?.device }
            .first
    }

    private func clearLatestFrame() {
        frameLock.lock()
        latestFrame = nil
        frameLock.unlock()
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameLock.lock()
        latestFrame = buffer
        let handler = _frameHandler
        frameLock.unlock()
        handler?(buffer)
    }
}
