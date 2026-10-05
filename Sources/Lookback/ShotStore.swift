import Foundation

/// Screenshot storage: ~/.lookback/<timestamp>[__<app>[__<detail>]].jpg.
/// - Part 1 (always): YYYY-MM-DD_HH-mm-ss capture time.
/// - Part 2 (optional): frontmost app display name.
/// - Part 3 (optional): domain for Chrome, project folder for VSCode.
/// Old timestamp-only files keep working (app/detail parse as nil).
enum ShotStore {
    /// Separator between the 3 parts. Safe because the timestamp contains
    /// only single "_" and sanitized app/detail never contain "__".
    static let sep = "__"
    static var dir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let d = home.appendingPathComponent(".lookback", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()

    struct Shot: Identifiable, Hashable {
        let id = UUID()
        let url: URL
        let date: Date
        /// Part 2: frontmost app at capture time, nil when unknown.
        let app: String?
        /// Part 3: domain (Chrome) / project folder (VSCode), nil otherwise.
        let detail: String?
    }

    /// Build "TS[__app[__detail]].jpg" filename. Empty app/detail are dropped,
    /// so context failures degrade to the old timestamp-only name.
    static func filename(for date: Date, app: String?, detail: String?) -> String {
        var name = fmt.string(from: date)
        if let a = sanitize(app), !a.isEmpty {
            name += sep + a
            if let d = sanitize(detail), !d.isEmpty {
                name += sep + d
            }
        }
        return name + ".jpg"
    }

    /// Strip characters that would break parsing or the filesystem.
    /// Returns nil for nil/blank input.
    static func sanitize(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines),
              !t.isEmpty else { return nil }
        var out = t
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        while out.contains(sep) {
            out = out.replacingOccurrences(of: sep, with: "_")
        }
        let clean = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    /// Parse a filename back into (date, app, detail). The timestamp is
    /// always the fixed 19-char prefix "yyyy-MM-dd_HH-mm-ss".
    static func parse(_ stem: String) -> (date: Date, app: String?, detail: String?)? {
        guard stem.count >= 19,
              let d = fmt.date(from: String(stem.prefix(19))) else { return nil }
        let rest = String(stem.dropFirst(19))
        guard !rest.isEmpty else { return (d, nil, nil) }
        guard rest.hasPrefix(sep) else { return nil }
        let parts = String(rest.dropFirst(sep.count)).components(separatedBy: sep)
        guard parts.count <= 2, !parts.contains(where: \.isEmpty) else { return nil }
        return (d, parts[0], parts.count == 2 ? parts[1] : nil)
    }

    static func list() -> [Shot] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles)
        else { return [] }
        var out: [Shot] = []
        for u in files where u.pathExtension.lowercased() == "jpg" {
            let name = u.deletingPathExtension().lastPathComponent
            if let p = parse(name) {
                out.append(Shot(url: u, date: p.date, app: p.app, detail: p.detail))
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    /// Nearest shot within tolerance seconds.
    static func nearest(to date: Date, in shots: [Shot], tolerance: TimeInterval = 90) -> Shot? {
        var best: Shot?
        var bestDelta = tolerance
        for s in shots {
            let delta = abs(s.date.timeIntervalSince(date))
            if delta <= bestDelta { bestDelta = delta; best = s }
        }
        return best
    }

    /// Delete files older than `days`. Runs on background queue.
    static func cleanup(olderThanDays days: Double = 7) {
        let cutoff = Date().addingTimeInterval(-days * 86400)
        for s in list() where s.date < cutoff {
            try? FileManager.default.removeItem(at: s.url)
        }
    }
}
