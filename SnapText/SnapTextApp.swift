import SwiftUI

@main
struct SnapTextApp: App {
    @StateObject private var store = CaptureStore()

    var body: some Scene {
        WindowGroup {
            ScannerView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
