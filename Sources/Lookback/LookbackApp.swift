import SwiftUI

@main
struct LookbackApp: App {
    @StateObject private var cap = CaptureService()

    var body: some Scene {
        Window("Lookback", id: "main") {
            TimelineView().environmentObject(cap)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(cap.paused ? "Tiếp tục chụp" : "Tạm dừng chụp") { cap.paused.toggle() }
            }
        }

        MenuBarExtra("Lookback", systemImage: "clock.arrow.circlepath") {
            Button("Mở cửa sổ Lookback") { NSApp.activate(ignoringOtherApps: true) }
            Button(cap.paused ? "Tiếp tục chụp" : "Tạm dừng chụp") { cap.paused.toggle() }
            Divider()
            Button("Thoát") { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
    }
}
