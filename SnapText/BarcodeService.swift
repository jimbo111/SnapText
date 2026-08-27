import CoreVideo
import Vision

/// A machine-readable code found in a frame.
struct DetectedCode: Equatable {
    let payload: String
    let symbology: VNBarcodeSymbology
}

enum BarcodeService {
    /// Restricting the symbology set keeps Vision from running detectors for
    /// exotic formats on every frame; these cover QR plus retail/logistics codes.
    static let symbologies: [VNBarcodeSymbology] = [
        .qr, .microQR, .aztec, .dataMatrix, .pdf417,
        .ean13, .ean8, .upce, .code128, .code39, .code93,
        .itf14, .i2of5, .codabar,
    ]

    /// Detects barcodes/QR codes in a camera frame. Blocking; call off the main thread.
    /// - Parameter regionOfInterest: normalized Vision rect (bottom-left origin) to restrict detection.
    static func detectCodes(
        in pixelBuffer: CVPixelBuffer,
        regionOfInterest: CGRect? = nil
    ) throws -> [DetectedCode] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = symbologies
        if let regionOfInterest {
            request.regionOfInterest = regionOfInterest
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try handler.perform([request])

        var seen = Set<String>()
        return (request.results ?? []).compactMap { observation in
            guard let payload = observation.payloadStringValue,
                  !payload.isEmpty,
                  seen.insert(payload).inserted
            else { return nil }
            return DetectedCode(payload: payload, symbology: observation.symbology)
        }
    }
}

extension VNBarcodeSymbology {
    var displayName: String {
        switch self {
        case .qr: "QR"
        case .microQR: "Micro QR"
        case .aztec: "Aztec"
        case .dataMatrix: "Data Matrix"
        case .pdf417: "PDF417"
        case .ean13: "EAN-13"
        case .ean8: "EAN-8"
        case .upce: "UPC-E"
        case .code128: "Code 128"
        case .code39: "Code 39"
        case .code93: "Code 93"
        case .itf14: "ITF-14"
        case .i2of5: "Interleaved 2 of 5"
        case .codabar: "Codabar"
        default: rawValue.replacingOccurrences(of: "VNBarcodeSymbology", with: "")
        }
    }
}
