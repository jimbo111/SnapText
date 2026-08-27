import CoreVideo
import Vision

enum OCRService {
    /// Recognizes text in a camera frame. Blocking; call off the main thread.
    /// - Parameters:
    ///   - regionOfInterest: normalized Vision rect (bottom-left origin) to restrict recognition.
    ///   - fast: trades accuracy for speed; used by the live preview, not for saved captures.
    static func recognizeText(
        in pixelBuffer: CVPixelBuffer,
        regionOfInterest: CGRect? = nil,
        fast: Bool = false
    ) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = fast ? .fast : .accurate
        request.usesLanguageCorrection = !fast
        // Language detection adds a per-frame cost the throttled preview doesn't
        // need; only the accurate save path pays for it.
        request.automaticallyDetectsLanguage = !fast
        if let regionOfInterest {
            request.regionOfInterest = regionOfInterest
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try handler.perform([request])

        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}
