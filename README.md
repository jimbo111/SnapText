# SnapText

Point. Scan. Saved.

SnapText is a fast, single-purpose iOS scanner built for **codes**: point your iPhone at a QR code or barcode and it's saved instantly — no tap needed. Every code you sweep the camera across lands in your captures list, deduplicated, ready to copy, share, open, or export. A text mode is still there for the moments you need OCR: tap once and the current frame's text is saved.

No account, no network calls, no third-party dependencies. All recognition happens on-device with Apple's Vision framework.

## Features

- **Code mode (default)** — live barcode detection runs near frame rate on the camera feed. The moment a code is sighted it's saved automatically with haptic and toast feedback. Supported symbologies: QR, Micro QR, Aztec, Data Matrix, PDF417, EAN-13/8, UPC-E, Code 128/39/93, ITF-14, Interleaved 2 of 5, and Codabar.
- **Deduplication** — a code saves once per sighting; holding the camera on it won't spam your list. Move it out of frame for a couple of seconds and it's eligible again, so batch-scanning a pile of labels just works.
- **Text mode** — one tap grabs the latest live video frame (no photo-capture latency), OCRs it with Vision's accurate recognizer, and saves the text. A throttled live preview chip shows what the camera is currently reading.
- **Capture region** — toggle a draggable, resizable frame to restrict scanning to just the part of the scene you care about (one label on a crowded shelf, one code on a dense page). Detection is limited via Vision's region of interest.
- **Pinch to zoom** — get closer to small or distant codes without moving.
- **Camera controls** — flip between front and back cameras, torch for dim scenes.
- **Captures list** — everything you saved, newest first, with search. Code captures carry a symbology badge; URL payloads get an Open Link button. Open any capture for the full content, copy it, or share it.
- **Export** — share all captures at once, copy them to the clipboard, or save them as a plain-text file to Files.
- **Local persistence** — captures are stored as JSON in the app's Documents directory and survive relaunches.

## Requirements

- iOS 17.0+
- Xcode 16+ (project uses buildable-folder synchronized groups)
- A physical iPhone to actually scan — the Simulator has no camera

## Building

1. Clone the repo and open `SnapText.xcodeproj`.
2. Select your development team under **Signing & Capabilities** (any free Apple ID works for personal use).
3. Choose your iPhone as the run destination and hit Run.

On first run, iOS will ask for camera permission and — for a personally signed build — you may need to trust the developer certificate in Settings → General → VPN & Device Management.

## How it works

| Component | Role |
|---|---|
| `CameraService` | Owns the `AVCaptureSession`. Configures on a background queue for fast startup, keeps the most recent video frame, handles flip/torch/zoom. Frames are delivered upright (`videoRotationAngle = 90`) in the sensor's native YCbCr format so Vision consumes them without a per-frame color conversion. |
| `BarcodeService` | Thin wrapper over `VNDetectBarcodesRequest`, restricted to common symbologies for speed, optional region of interest. |
| `LiveCodeDetector` | Throttled (~6–7 Hz) barcode detection on the live feed. Auto-saves each newly sighted code and dedupes with a per-payload cooldown shared with manual taps. |
| `OCRService` | Thin wrapper over `VNRecognizeTextRequest`. Accurate + language-corrected for saved captures; the fast live-preview path skips language detection entirely. |
| `LiveTextDetector` | Throttled (~2.5 Hz) fast OCR on the live feed feeding the text-mode preview chip. |
| `CropState` / `CropBoxOverlay` | The capture-region frame. `CropState` maps the on-screen rectangle through the aspect-fill preview into Vision's normalized, bottom-left-origin region of interest, including the front-camera mirror flip. |
| `CaptureStore` | Observable model + JSON persistence in Documents. Encoding and disk writes happen on a serial background queue so rapid-fire scanning never blocks the UI. |
| `ScannerView` / `CapturesListView` | SwiftUI UI: full-screen preview with a Code/Text mode switch, auto-capture in code mode, tap-to-capture in text mode, and the saved-captures list with search, share, copy, delete, and file export. |

The capture path is deliberately built on `AVCaptureVideoDataOutput` rather than photo capture: the frame the detector sees is already in memory, so a scan costs only the Vision time, not shutter latency.

## Privacy

SnapText makes no network requests. Camera frames are processed in memory by the on-device Vision framework; only the code payloads and text you capture are written to disk, inside the app's own sandbox.

## License

MIT — see [LICENSE](LICENSE).
