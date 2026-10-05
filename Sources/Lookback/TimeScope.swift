import Foundation

/// App-wide time scope: the sidebar preset lives here so Timeline AND Stats
/// filter the same window. Single owner (`MainView`), passed down.
final class TimeScope: ObservableObject {
    enum Preset: String, CaseIterable, Identifiable {
        case last1h = "1 giờ qua"
        case last6h = "6 giờ qua"
        case last24h = "24 giờ qua"
        case today = "Hôm nay"
        case yesterdayAM = "Sáng hôm qua"
        var id: String { rawValue }

        func window(now: Date = Date()) -> (Date, Date) {
            let cal = Calendar.current
            switch self {
            case .last1h: return (now.addingTimeInterval(-3600), now)
            case .last6h: return (now.addingTimeInterval(-6 * 3600), now)
            case .last24h: return (now.addingTimeInterval(-24 * 3600), now)
            case .today: return (cal.startOfDay(for: now), now)
            case .yesterdayAM:
                let y = cal.date(byAdding: .day, value: -1, to: now) ?? now
                let start = cal.date(bySettingHour: 6, minute: 0, second: 0, of: y) ?? y
                let end = cal.date(bySettingHour: 12, minute: 0, second: 0, of: y) ?? y
                return (start, end)
            }
        }
    }

    @Published var preset: Preset = .last24h
    /// Frozen window edges for the current preset (refreshed on preset change
    /// or reload, so `Date()` drift doesn't rebuild state every body pass).
    @Published private(set) var from: Date = Date().addingTimeInterval(-24 * 3600)
    @Published private(set) var to: Date = Date()

    func refreshWindow(now: Date = Date()) {
        let (f, t) = preset.window(now: now)
        from = f; to = t
    }
}
