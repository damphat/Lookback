import SwiftUI

@main
struct LookbackApp: App {
    @StateObject private var cap = CaptureService()

    var body: some Scene {
        MenuBarExtra("Lookback", systemImage: "clock.arrow.circlepath") {
            TimelineView().environmentObject(cap)
            Divider()
            Button(cap.paused ? "Tiếp tục chụp" : "Tạm dừng chụp") { cap.paused.toggle() }
            Button("Thoát") { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.window)
    }
}
