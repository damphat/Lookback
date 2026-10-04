import SwiftUI

@main
struct LookbackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    // Settings scene = no window at launch; the window is created
    // on demand by AppDelegate (tray left-click / menu).
    var body: some Scene {
        Settings { EmptyView() }
    }
}
