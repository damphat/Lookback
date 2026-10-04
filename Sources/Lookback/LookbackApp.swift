import SwiftUI

@main
struct LookbackApp: App {
    @StateObject private var cap = CaptureService.shared

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
            MenuBarMenu().environmentObject(cap)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Menu-bar dropdown. Uses openWindow so "Mở cửa sổ" really reopens
/// the window even after the user closed it (activate() alone can't).
struct MenuBarMenu: View {
    @EnvironmentObject var cap: CaptureService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Mở cửa sổ Lookback") { openWindow(id: "main") }
        Button(cap.paused ? "Tiếp tục chụp" : "Tạm dừng chụp") { cap.paused.toggle() }
        Divider()
        Button("Thoát") { NSApplication.shared.terminate(nil) }
    }
}
