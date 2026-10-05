import SwiftUI

/// Time axis for the activity bar: adaptive wall-clock ticks that never
/// overlap, with "now" pinned at the right edge when the window is live.
///
/// Pure `TimeRulerModel` (tested) picks the ticks; `TimeRuler` (thin view)
/// draws them. Reusable anywhere a [from, to] window needs an axis.
enum TimeRulerModel {
    struct Tick: Equatable {
        /// Fraction in [0, 1] across the window.
        let fraction: Double
        let label: String
    }

    /// Nice steps, seconds. Smallest step whose pixel gap clears minSpacing.
    private static let steps: [Double] = [60, 300, 900, 1800, 3600, 7200, 3 * 3600, 6 * 3600, 12 * 3600]

    private static let labelFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    static func ticks(from: Date, to: Date, width: CGFloat, minSpacing: CGFloat = 56) -> [Tick] {
        let span = to.timeIntervalSince(from)
        guard span > 0, width > 0 else { return [] }
        let step = steps.first { $0 / span * Double(width) >= Double(minSpacing) } ?? steps.last!
        // Epoch-anchored grid: stable labels while `to` drifts with "now".
        var t = Date(timeIntervalSince1970: ceil(from.timeIntervalSince1970 / step) * step)
        var out: [Tick] = []
        while t <= to {
            let f = t.timeIntervalSince(from) / span
            // Skip the right-edge slot: it belongs to "now" (or `to`).
            if f < 0.985 {
                out.append(Tick(fraction: f, label: labelFmt.string(from: t)))
            }
            t = t.addingTimeInterval(step)
            if out.count > 64 { break }
        }
        return out
    }

    /// Right-edge caption: "now" for a live window, else the end time.
    static func edgeLabel(to: Date, now: Date = Date()) -> String {
        abs(to.timeIntervalSince(now)) < 300 ? "now" : labelFmt.string(from: to)
    }
}

/// Thin axis view. Height 18: tick marks + labels, right-aligned edge label.
struct TimeRuler: View {
    let from: Date
    let to: Date

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let ticks = TimeRulerModel.ticks(from: from, to: to, width: w)
            ZStack(alignment: .topLeading) {
                ForEach(ticks.indices, id: \.self) { i in
                    Text(ticks[i].label)
                        .font(.caption2).foregroundStyle(.secondary)
                        .offset(x: min(max(ticks[i].fraction * w - 14, 0), max(0, w - 44)))
                }
                Text(TimeRulerModel.edgeLabel(to: to))
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(width: w, alignment: .trailing)
            }
        }
        .frame(height: 16)
    }
}
