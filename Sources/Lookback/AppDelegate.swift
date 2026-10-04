import AppKit
import CoreGraphics
import SwiftUI

/// Agent-style app: no Dock icon (LSUIElement), no window at launch.
/// Left-click tray icon = open + raise window, right-click = menu.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let cap = CaptureService.shared
    private var statusItem: NSStatusItem!
    private var windowController: NSWindowController?

    func applicationDidFinishLaunching(_ note: Notification) {
        cap.start()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "clock.arrow.circlepath",
                accessibilityDescription: "Lookback")
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        // Fresh install / overwrite without Screen Recording permission:
        // pop the window open so the user SEES the banner instead of
        // running blind all day with zero shots captured.
        if !CGPreflightScreenCaptureAccess() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showWindow() }
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { showWindow(); return }
        if event.type == .rightMouseUp {
            // NSStatusItem.popUpMenu is deprecated; NSMenu.popUp is the
            // supported way to show a status-item menu programmatically.
            trayMenu().popUp(positioning: nil,
                              at: NSPoint(x: 0, y: sender.bounds.maxY + 4),
                              in: sender)
        } else {
            showWindow()
        }
    }

    private func trayMenu() -> NSMenu {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Mở cửa sổ Lookback", action: #selector(showWindowFromMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let pauseTitle = cap.paused ? "Tiếp tục chụp" : "Tạm dừng chụp"
        let pause = NSMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "Về Lookback…", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: "Thoát", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func showWindowFromMenu() { showWindow() }
    @objc private func togglePause() { cap.paused.toggle() }
    /// Standard About panel: app name, icon, version (from Info.plist).
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }

    /// Window closed -> release everything (timers die with the view,
    /// thumbnails freed). Capture keeps running; reopening starts fresh.
    func windowWillClose(_ notification: Notification) {
        windowController = nil
    }

    /// Open the window if closed, raise + focus it if buried.
    @objc func showWindow() {
        if windowController == nil {
            let host = NSHostingController(
                rootView: TimelineView().environmentObject(cap))
            let win = NSWindow(contentViewController: host)
            win.title = "Lookback"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.setContentSize(NSSize(width: 700, height: 600))
            win.minSize = NSSize(width: 560, height: 480)
            win.isReleasedWhenClosed = false
            win.delegate = self
            windowController = NSWindowController(window: win)
        }
        NSApp.activate(ignoringOtherApps: true)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }
}
