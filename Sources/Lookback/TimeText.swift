/// One place for every duration string in the app: compact overlays,
/// popup lines, status lines. Minutes in, Vietnamese out — no caller formats
/// time by hand anymore.
enum TimeText {
    /// "57p", "3h", "3h05p" — cell overlays, tight spaces.
    static func short(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)p" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h\(String(format: "%02d", m))p"
    }

    /// "57 phút", "3 giờ", "3 giờ 5 phút" — popups, stats, status lines.
    static func long(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) phút" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) giờ" : "\(h) giờ \(m) phút"
    }

    /// "hiện tại", "5 phút trước", "3h05p trước" — relative position labels.
    static func ago(_ minutes: Int) -> String {
        if minutes < 1 { return "hiện tại" }
        if minutes < 60 { return "\(minutes) phút trước" }
        return "\(short(minutes)) trước"
    }
}
