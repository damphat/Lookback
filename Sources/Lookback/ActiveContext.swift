import AppKit
import Foundation

/// Best-effort "what is the user doing right now" context for filenames.
/// Never throws, never blocks the capture loop: every step degrades to nil.
///
/// - App name: `NSWorkspace.frontmostApplication` — no permission needed.
/// - Chrome domain: AppleScript `URL of active tab`. macOS may ask for
///   Automation permission once; if the user denies, this just stays nil.
/// - VSCode folder: frontmost VSCode window title via CGWindowList
///   (no permission needed), last path component only.
enum ActiveContext {
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

        let detail: String?
        if bundleID == "com.google.Chrome"
            || name?.lowercased().contains("chrome") == true {
            detail = chromeDomain()
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

    /// Domain of the active tab, e.g. "github.com". Nil when Chrome is not
    /// scriptable right now (no window, permission denied, ...).
    private static func chromeDomain() -> String? {
        let src = "tell application \"Google Chrome\" to get URL of active tab of front window"
        guard let script = NSAppleScript(source: src) else { return nil }
        var err: NSDictionary?
        let result = script.executeAndReturnError(&err)
        guard err == nil, result.stringValue != nil else { return nil }
        guard let urlString = result.stringValue,
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
