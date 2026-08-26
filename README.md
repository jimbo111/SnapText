# SnapText

Point. Tap. Saved.

SnapText is a fast, single-purpose iOS scanner: point your iPhone at any text — a monitor, a slide, a whiteboard, a page — and tap the screen once. The current camera frame is run through on-device OCR and the recognized text is saved instantly. Repeat as fast as you can tap. When you're done, everything you captured is waiting in a list, ready to copy, share, or export.

No account, no network calls, no third-party dependencies. All recognition happens on-device with Apple's Vision framework.

## Features

- **One-tap capture** — the tap grabs the latest live video frame (no photo-capture latency), OCRs it with Vision's accurate recognizer, and saves the text with haptic and flash feedback.
- **Live text preview** — a lightweight recognition pass runs on the camera feed and shows a chip with the first line the camera is currently reading, so you know a tap will land before you take it.
- **Capture region** — toggle a draggable, resizable frame to restrict OCR to just the part of the scene you care about (ignore menus, ads, or side panels). Recognition is limited via Vision's region of interest.
- **Pinch to zoom** — get closer to small or distant text without moving.
- **Camera controls** — flip between front and back cameras, torch for dim scenes.
- **Captures list** — everything you saved, newest first, with search. Open any capture for the full text, copy it, or share it.
- **Export** — share all captures at once (Notes, Messages, anywhere the share sheet reaches), copy them to the clipboard, or save them as a plain-text file to Files.
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
| `CameraService` | Owns the `AVCaptureSession`. Configures on a background queue for fast startup, keeps the most recent video frame, handles flip/torch/zoom. Frames are delivered upright (`videoRotationAngle = 90`) so OCR sees natural orientation. |
| `OCRService` | Thin wrapper over `VNRecognizeTextRequest`. Accurate + language-corrected for saved captures, fast mode for the live preview, optional region of interest. |
| `LiveTextDetector` | Throttled (~2.5 Hz) fast OCR on the live feed feeding the preview chip. |
| `CropState` / `CropBoxOverlay` | The capture-region frame. `CropState` maps the on-screen rectangle through the aspect-fill preview into Vision's normalized, bottom-left-origin region of interest, including the front-camera mirror flip. |
| `CaptureStore` | Observable model + JSON persistence in Documents. |
| `ScannerView` / `CapturesListView` | SwiftUI UI: full-screen preview with tap-to-capture, and the saved-captures list with search, share, copy, delete, and file export. |

The capture path is deliberately built on `AVCaptureVideoDataOutput` rather than photo capture: the frame you see is already in memory, so a tap costs only the OCR time, not shutter latency.

## Privacy

SnapText makes no network requests. Camera frames are processed in memory by the on-device Vision framework; only the recognized text you explicitly capture is written to disk, inside the app's own sandbox.

## License

MIT — see [LICENSE](LICENSE).
