import Foundation

/// Screenshot storage: ~/.lookback/YYYY-MM-DD_HH-mm-ss.jpg, retention 7 days.
enum ShotStore {
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
    }

    static func list() -> [Shot] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles)
        else { return [] }
        var out: [Shot] = []
        for u in files where u.pathExtension.lowercased() == "jpg" {
            let name = u.deletingPathExtension().lastPathComponent
            if let d = fmt.date(from: name) {
                out.append(Shot(url: u, date: d))
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
