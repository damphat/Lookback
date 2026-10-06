import AppKit
import Combine
import CoreGraphics
import SwiftUI

/// Pure quit policy, testable without NSApp: default-deny, opened only by
/// the tray "Thoát" item or by macOS ending the session.
struct QuitGate {
    var allowQuit = false
    var systemShutdown = false
    var shouldTerminate: Bool { allowQuit || systemShutdown }
}

/// Pure tray mapping, testable without NSApp. One disambiguation rule:
/// the icon always shows STATE (same face, dimmed when stopped), the menu
/// item always shows ACTION (a verb naming what the click will do). Never
/// a ⏸ glyph on the icon — nobody can tell whether it means "stopped now"
/// or "click to stop".
enum TrayState {
    static let symbol = "clock.arrow.circlepath"
    static func dimmed(paused: Bool) -> Bool { paused }
    static func toolTip(paused: Bool) -> String {
        paused ? "Lookback (đang dừng chụp)" : "Lookback"
    }
    static func menuTitle(paused: Bool) -> String {
        paused ? "Tiếp tục chụp" : "Tạm dừng chụp"
    }
}

/// Agent-style app: no Dock icon (LSUIElement), no window at launch.
/// Left-click tray icon = open + raise window, right-click = menu.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let cap = CaptureService.shared
    private var statusItem: NSStatusItem!
    private var windowController: NSWindowController?
    private var pauseWatch: AnyCancellable?
    /// Quit gate: only the tray "Thoát" item opens it. Everything else that
    /// asks to quit (accidental Cmd+Q) is vetoed; real logout/restart/
    /// shutdown still goes through.
    private var quitGate = QuitGate()

    /// Cmd+Q lands here with no main-menu item to strip (LSUIElement app).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitGate.shouldTerminate ? .terminateNow : .terminateCancel
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(noteShutdown),
            name: NSWorkspace.willPowerOffNotification, object: nil)
        cap.start()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refreshTrayIcon(paused: cap.paused)
        // Pass the emitted value through: @Published fires from willSet, so
        // re-reading cap.paused in here sees the PREVIOUS state (tray lagged
        // one toggle behind, then read inverted). Never re-read in a sink.
        pauseWatch = cap.$paused.sink { [weak self] paused in
            self?.refreshTrayIcon(paused: paused)
        }
        // Missing EITHER gate (Recording or Automation — both checked in
        // start()): pop the window open so the user SEES the banner instead
        // of running blind with a silent denial.
        if !cap.permissionGranted || cap.automationDenied {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showWindow() }
        }
    }

    /// Single place that draws the tray icon. Same face always; stopped
    /// reads as dimmed + tooltip. Takes the state as a parameter — callers
    /// pass the fresh value, never a re-read inside a Combine sink.
    private func refreshTrayIcon(paused: Bool) {
        guard let button = statusItem?.button else { return }
        button.image = NSImage(
            systemSymbolName: TrayState.symbol,
            accessibilityDescription: "Lookback")
        button.appearsDisabled = TrayState.dimmed(paused: paused)
        button.toolTip = TrayState.toolTip(paused: paused)
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

    /// The ONLY capture control in the app: one start/stop toggle.
    /// (Left-click opens the window; the in-window checkbox is gone.)
    private func trayMenu() -> NSMenu {
        let menu = NSMenu()
        let pause = NSMenuItem(title: TrayState.menuTitle(paused: cap.paused), action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Thoát", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func togglePause() { cap.paused.toggle() }
    /// The ONLY user path that quits the app: right-click tray → Thoát.
    @objc private func quitApp() {
        quitGate.allowQuit = true
        NSApplication.shared.terminate(nil)
    }

    @objc private func noteShutdown() { quitGate.systemShutdown = true }

    /// Remembered frame (UserDefaults): the window reopens at the size the
    /// user left it instead of snapping back to the default every time.
    private static let frameKey = "lookback.windowFrame"
    private static let defaultSize = NSSize(width: 1160, height: 720)

    /// Window closed -> persist the frame, then release everything (timers
    /// die with the view, thumbnails freed). Capture keeps running;
    /// reopening restores the remembered size.
    func windowWillClose(_ notification: Notification) {
        if let win = (notification.object as? NSWindow) ?? windowController?.window {
            saveFrame(win.frame)
        }
        NotificationCenter.default.removeObserver(
            self, name: NSWindow.didResizeNotification, object: windowController?.window)
        NotificationCenter.default.removeObserver(
            self, name: NSWindow.didMoveNotification, object: windowController?.window)
        windowController = nil
    }

    private func saveFrame(_ frame: NSRect) {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.frameKey)
    }

    @objc private func noteFrameChanged(_ note: Notification) {
        if let win = note.object as? NSWindow { saveFrame(win.frame) }
    }

    /// Open the window if closed, raise + focus it if buried.
    @objc func showWindow() {
        if windowController == nil {
            let host = NSHostingController(
                rootView: MainView().environmentObject(cap))
            let win = NSWindow(contentViewController: host)
            win.title = "Lookback"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.minSize = NSSize(width: 900, height: 580)
            let visible = NSScreen.main?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1728, height: 1079)
            let saved: CGRect? = UserDefaults.standard.string(forKey: Self.frameKey)
                .map(NSRectFromString)
                .flatMap { $0.isEmpty ? nil : $0 }
            win.setFrame(
                WindowFrame.restored(
                    saved: saved, minSize: win.minSize,
                    defaultSize: Self.defaultSize, visible: visible),
                display: false)
            win.isReleasedWhenClosed = false
            win.delegate = self
            NotificationCenter.default.addObserver(
                self, selector: #selector(noteFrameChanged),
                name: NSWindow.didResizeNotification, object: win)
            NotificationCenter.default.addObserver(
                self, selector: #selector(noteFrameChanged),
                name: NSWindow.didMoveNotification, object: win)
            windowController = NSWindowController(window: win)
        }
        NSApp.activate(ignoringOtherApps: true)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }
}
