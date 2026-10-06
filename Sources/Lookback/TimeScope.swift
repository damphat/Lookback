import Foundation

/// App-wide time scope: the sidebar preset lives here so Timeline AND Stats
/// filter the same window. Single owner (`MainView`), passed down.
///
/// Mental model (covers TODO 1+3 with one rule):
/// - Window = f(preset, now). `tick` is the ONLY writer of from/to.
///   Trailing presets ride "now" on every tick; fixed ones only on force.
/// - Selection is a trailing-edge pin: within `liveEps` of `to` means
///   "watching now", so every rescope rides the edge; otherwise clamp.
/// - The preset persists in UserDefaults, so reopening keeps the setting.
final class TimeScope: ObservableObject {
    enum Preset: String, CaseIterable, Identifiable {
        case last1h = "1 giờ qua"
        case last6h = "6 giờ qua"
        case last24h = "24 giờ qua"
        case today = "Hôm nay"
        case yesterdayAM = "Sáng hôm qua"
        var id: String { rawValue }

        /// Trailing presets end at "now" and keep moving; the rest are fixed.
        var followsNow: Bool { self != .yesterdayAM }

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

    private static let presetKey = "lookback.timePreset"
    /// Within this far of `to` counts as "watching now" (~1.5 capture ticks).
    static let liveEps: TimeInterval = 90

    private let defaults: UserDefaults
    @Published var preset: Preset {
        didSet { defaults.set(preset.rawValue, forKey: Self.presetKey) }
    }
    /// Frozen window edges for the current preset (only `tick` writes them,
    /// so `Date()` drift doesn't rebuild state every body pass).
    @Published private(set) var from: Date = Date().addingTimeInterval(-24 * 3600)
    @Published private(set) var to: Date = Date()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: Self.presetKey).flatMap(Preset.init(rawValue:))
        self.preset = saved ?? .last24h
    }

    /// The ONLY writer of from/to. Trailing presets ride "now" on every
    /// call; fixed ones only when forced (preset just changed / first open).
    /// Skips the write when nothing moved, so idle ticks don't rebuild views.
    func tick(now: Date = Date(), force: Bool = false) {
        guard preset.followsNow || force else { return }
        let (f, t) = preset.window(now: now)
        if abs(f.timeIntervalSince(from)) > 1 || abs(t.timeIntervalSince(to)) > 1 {
            from = f; to = t
        }
    }

    /// Trailing-edge pin: near `to` means "watching now" — ride the edge.
    static func isLive(_ selected: Date, to: Date) -> Bool {
        to.timeIntervalSince(selected) < liveEps
    }
}
