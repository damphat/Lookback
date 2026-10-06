import AppKit
import CoreServices
import Foundation

/// Best-effort "what is the user doing right now" context for filenames.
/// Never throws, never blocks the capture loop: every step degrades to nil.
///
/// - App name: `NSWorkspace.frontmostApplication` — no permission needed.
/// - Chrome domain: AppleScript `URL of active tab`. Needs Automation
///   consent (Lookback → Chrome); a deny is sticky-detectable via
///   `chromeDenied` so the UI can point at Settings (mirrors the Screen
///   Recording banner). The check never prompts by itself.
/// - VSCode folder: frontmost VSCode window title via CGWindowList
///   (no permission needed), last path component only.
enum ActiveContext {
    /// Sticky denial latch: set the moment Chrome is frontmost without
    /// consent, cleared only when a live check proves consent granted.
    /// Never cleared by "Chrome isn't frontmost right now" — that flip-flop
    /// was the banner blinking on/off every capture cycle. Drives the banner.
    static var chromeDenied = false
    struct Info {
        /// Display name of the frontmost app, e.g. "Google Chrome".
        let app: String?
        /// Part 3: domain for Chrome, folder name for VSCode, else nil.
        let detail: String?
    }

    static func current() -> Info {
        guard let front = NSWorkspace.shared.frontmostApplication else {
            return Info(app: nil, detail: nil)
        }
        let bundleID = front.bundleIdentifier ?? ""
        let appName = front.localizedName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (appName?.isEmpty == false) ? appName : nil
        let isChrome = bundleID == "com.google.Chrome"
            || name?.lowercased().contains("chrome") == true
        // Latch discipline: only a live Chrome moment may touch the latch.
        // Anything else leaves it alone, so the banner can't blink.
        if isChrome { chromeDenied = chromeAutomationDenied() }

        let detail: String?
        if isChrome {
            detail = chromeDenied ? nil : chromeDomain()
        } else if bundleID == "com.microsoft.VSCode"
            || name == "Visual Studio Code"
            || name == "Code" {
            detail = vscodeFolder(pid: front.processIdentifier)
        } else {
            detail = nil
        }
        return Info(app: name, detail: detail)
    }

    // MARK: - Chrome

    /// Pure mapping of the permission-check status: anything but noErr
    /// (-1743 denied, -1744 consent required, ...) counts as denied.
    static func automationDenied(status: OSStatus) -> Bool { status != noErr }

    /// User-initiated consent request (banner "Cấp quyền…" button). THIS is
    /// the only path that pops the system dialog and creates the Automation
    /// entry for the current binary — the background loop deliberately never
    /// does (`askUserIfNeeded: false`), so a fresh install can never get
    /// listed without this tap. Returns true when consent is now granted.
    @discardableResult
    static func requestChromeAutomation() -> Bool {
        guard var target = chromeTarget() else { return false }
        defer { AEDisposeDesc(&target) }
        let status = AEDeterminePermissionToAutomateTarget(
            &target, AEEventClass(kAECoreSuite), AEEventID(kAEGetData), true)
        return !automationDenied(status: status)
    }

    private static func chromeTarget() -> AEAddressDesc? {
        var target = AEAddressDesc()
        let bid = "com.google.Chrome"
        let made = bid.utf8CString.withUnsafeBufferPointer { buf in
            AECreateDesc(typeApplicationBundleID, buf.baseAddress,
                         buf.count, &target)
        }
        guard made == noErr else { return nil }
        return target
    }

    /// Automation consent for scripting Chrome, WITHOUT prompting
    /// (`askUserIfNeeded: false` — the background loop must never pop a
    /// dialog; the banner asks the user to open Settings instead).
    static func chromeAutomationDenied() -> Bool {
        guard var target = chromeTarget() else { return false }
        defer { AEDisposeDesc(&target) }
        let status = AEDeterminePermissionToAutomateTarget(
            &target, AEEventClass(kAECoreSuite), AEEventID(kAEGetData), false)
        return automationDenied(status: status)
    }

    /// Compiled once, reused every call. Benchmark (Oct 2026, this Mac):
    /// init/compile is ~0.01ms, but a fresh NSAppleScript + execute costs
    /// ~45ms vs ~15ms on a reused instance — the per-call engine/channel
    /// setup dominates, not compilation. (Swift `static let` inits lazily
    /// and thread-safely on first use.)
    private static let chromeScript = NSAppleScript(source:
        "tell application \"Google Chrome\" to get URL of active tab of front window")
    /// NSAppleScript isn't documented thread-safe and the capture loop runs
    /// off-main, so execution is serialized. Lock cost (~ns) is noise next
    /// to the ~15ms AppleEvent round-trip.
    private static let chromeScriptLock = NSLock()

    /// Domain of the active tab, e.g. "github.com". Nil when Chrome is not
    /// scriptable right now (no window, ...). Caller has already proven
    /// consent, so this never touches the latch.
    private static func chromeDomain() -> String? {
        chromeScriptLock.lock()
        defer { chromeScriptLock.unlock() }
        var err: NSDictionary?
        let result = chromeScript?.executeAndReturnError(&err)
        guard err == nil, let urlString = result?.stringValue,
              let host = URL(string: urlString)?.host,
              !host.isEmpty else { return nil }
        var domain = host.lowercased()
        if domain.hasPrefix("www.") { domain = String(domain.dropFirst(4)) }
        return domain.isEmpty ? nil : domain
    }

    // MARK: - VSCode

    /// Last folder name from the frontmost VSCode window title.
    /// Titles look like "AppDelegate.swift — Lookback — Visual Studio Code",
    /// so after dropping the app suffix the folder is the last component.
    private static func vscodeFolder(pid: pid_t) -> String? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID) as? [[String: Any]] else { return nil }
        // Windows come front-to-back; first VSCode match is the frontmost.
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? Int32) == pid,
                  var title = w[kCGWindowName as String] as? String,
                  !title.isEmpty else { continue }
            if let r = title.range(of: "Visual Studio Code", options: .backwards) {
                title = String(title[..<r.lowerBound])
            }
            let parts = title
                .components(separatedBy: CharacterSet(charactersIn: "—-"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard let folder = parts.last else { continue }
            return folder.isEmpty ? nil : folder
        }
        return nil
    }
}
