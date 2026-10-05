import AppKit
import SwiftUI

/// A lookback-style activity bar: one continuous colour band per app session,
/// built from the day's screenshots.
///
/// - Each contiguous run of the same app (part 2 of the filename) is one
///   solid segment; gaps with no shots stay transparent (idle time).
/// - Hovering lights up the whole segment and floats a popup above the bar:
///   app name, time range + duration, and the exact shot under the cursor.
/// - Clicking selects that shot (playhead jumps + `onSelect` fires).
/// - `from`/`to` make the observed window explicit, so the same bar works
///   for "last 24h", "today", or any custom range.
///
/// Colours are stable per app name (hash → hue), using the system accent
/// only for the playhead — no decorative gradients.
struct AppActivityBar: View {
    let shots: [ShotStore.Shot]
    let from: Date
    let to: Date
    @Binding var selectedDate: Date
    var onSelect: (ShotStore.Shot) -> Void = { _ in }

    @State private var hoverX: CGFloat? = nil

    private let barHeight: CGFloat = 34

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                let segs = AppActivityBarModel.segments(
                    shots: shots, from: from, to: to)
                let gaps = AppActivityBarModel.idles(
                    shots: shots, from: from, to: to)
                ZStack(alignment: .bottomLeading) {
                    // Track: idle background + hour ticks.
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(nsColor: .separatorColor).opacity(0.35))
                        .frame(height: barHeight)
                    ForEach(AppActivityBarModel.ticks(from: from, to: to),
                            id: \.self) { t in
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor))
                            .frame(width: 1, height: barHeight)
                            .offset(x: x(t, in: w))
                    }
                    // App segments. The hover ring is a SIBLING with the
                    // same frame + offset as the fill (never an overlay),
                    // so it can never detach to another position.
                    ForEach(segs) { seg in
                        let hov = isHovered(seg, width: w)
                        let segW = max(3, x(seg.end, in: w) - x(seg.start, in: w))
                        let segX = x(seg.start, in: w)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(AppActivityBarModel.color(for: seg.app))
                            .opacity(hov ? 1.0 : 0.72)
                            .frame(width: segW, height: barHeight)
                            .offset(x: segX)
                            .shadow(color: hov
                                    ? AppActivityBarModel.color(for: seg.app).opacity(0.55)
                                    : .clear,
                                    radius: 6, y: 0)
                        if hov {
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5)
                                .frame(width: segW, height: barHeight)
                                .offset(x: segX)
                        }
                    }
                    // Playhead (bottom-aligned: stands 6pt proud of the bar).
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: barHeight + 6)
                        .offset(x: x(selectedDate, in: w) - 1)
                    // Transparent mouse layer (macOS 13-safe tracking).
                    // Press AND drag scrub the whole bar: every position
                    // maps to its nearest shot, not just segment taps.
                    MouseTracker(
                        onMove: { loc in hoverX = loc?.x },
                        onClick: { loc in moveSelection(to: loc.x, width: w, in: segs) },
                        onDrag: { loc in moveSelection(to: loc.x, width: w, in: segs) },
                        onRelease: { loc in
                            if let s = shot(at: loc.x, width: w, in: segs) {
                                onSelect(s)
                            }
                        }
                    )
                }
                .frame(height: barHeight)
                // Popup lives in an OVERLAY (zero layout footprint), so it
                // can never push the bar down or overlap the time labels.
                // Hit testing stays off: the mouse layer below keeps
                // receiving move/drag events while the card is up.
                .overlay(alignment: .bottomLeading) {
                    hoverPopup(segs: segs, gaps: gaps, width: w)
                        .allowsHitTesting(false)
                }
                .onHover { inside in
                    if inside {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                        hoverX = nil
                    }
                }
            }
            .frame(height: barHeight)
            // Time labels adapt to whatever (from, to) is configured.
            HStack {
                Text(AppActivityBarModel.tickLabel(from)); Spacer()
                Text(AppActivityBarModel.tickLabel(
                    Date(timeIntervalSince1970: (from.timeIntervalSince1970 + to.timeIntervalSince1970) / 2)))
                Spacer()
                Text(abs(to.timeIntervalSinceNow) < 300
                     ? "bây giờ" : AppActivityBarModel.tickLabel(to))
            }
            .font(.caption).foregroundStyle(.secondary)
            // Compact legend: colour → app → count.
            legend()
        }
    }

    // MARK: - Geometry helpers

    private func x(_ d: Date, in w: CGFloat) -> CGFloat {
        AppActivityBarModel.x(d, from: from, to: to, width: w)
    }

    private func segment(at px: CGFloat, width w: CGFloat,
                         in segs: [AppActivityBarModel.Segment]) -> AppActivityBarModel.Segment? {
        let t = AppActivityBarModel.date(at: px, from: from, to: to, width: w)
        return segs.first { $0.start <= t && t <= $0.end }
    }

    private func isHovered(_ seg: AppActivityBarModel.Segment, width w: CGFloat) -> Bool {
        guard let hx = hoverX else { return false }
        let t = AppActivityBarModel.date(at: hx, from: from, to: to, width: w)
        return seg.start <= t && t <= seg.end
    }

    private func shot(at px: CGFloat, width w: CGFloat,
                      in segs: [AppActivityBarModel.Segment]) -> ShotStore.Shot? {
        guard let seg = segment(at: px, width: w, in: segs) else { return nil }
        let t = AppActivityBarModel.date(at: px, from: from, to: to, width: w)
        return ShotStore.nearest(to: t, in: seg.shots, tolerance: .infinity)
    }

    /// Scrub the whole bar: move the playhead to the shot nearest the
    /// pointer and refresh the viewer. Shared by click and drag.
    private func moveSelection(to px: CGFloat, width w: CGFloat,
                               in segs: [AppActivityBarModel.Segment]) {
        if let s = shot(at: px, width: w, in: segs) {
            selectedDate = s.date
            onSelect(s)
        }
    }

    // MARK: - Hover popup (segment or idle)

    @ViewBuilder
    private func hoverPopup(segs: [AppActivityBarModel.Segment],
                            gaps: [AppActivityBarModel.Idle],
                            width w: CGFloat) -> some View {
        if let hx = hoverX {
            let t = AppActivityBarModel.date(at: hx, from: from, to: to, width: w)
            if let seg = segs.first(where: { $0.start <= t && t <= $0.end }),
               let shot = ShotStore.nearest(to: t, in: seg.shots, tolerance: .infinity) {
                hoverCard(seg: seg, shot: shot)
                    .offset(x: popupX(hx, width: w), y: -(barHeight + 8))
            } else if let gap = gaps.first(where: { $0.start <= t && t <= $0.end }) {
                idleCard(gap)
                    .offset(x: popupX(hx, width: w), y: -(barHeight + 8))
            }
        }
    }

    private func idleCard(_ gap: AppActivityBarModel.Idle) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.zzz")
                .font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Máy nghỉ").font(.headline)
                Text("\(AppActivityBarModel.tickLabel(gap.start)) → \(AppActivityBarModel.tickLabel(gap.end)) • \(gap.minutes) phút • 0 ảnh")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 236, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 8)
    }

    private func popupX(_ hx: CGFloat, width w: CGFloat) -> CGFloat {
        let cardW: CGFloat = 236
        return min(max(hx - cardW / 2, 0), max(0, w - cardW))
    }

    // MARK: - Popup + legend

    private func hoverCard(seg: AppActivityBarModel.Segment,
                           shot: ShotStore.Shot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(AppActivityBarModel.color(for: seg.app))
                    .frame(width: 10, height: 10)
                Text(seg.app).font(.headline).lineLimit(1)
                Spacer()
                Text("\(seg.shots.count) ảnh")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("\(AppActivityBarModel.tickLabel(seg.start)) → \(AppActivityBarModel.tickLabel(seg.end)) • \(Int(round(seg.end.timeIntervalSince(seg.start) / 60))) phút")
                .font(.caption).foregroundStyle(.secondary)
            if let img = ThumbCache.thumb(for: shot, width: 220) {
                Image(nsImage: img)
                    .resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Text("Ảnh lúc \(AppActivityBarModel.tickLabel(shot.date)) — bấm để xem")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(width: 236, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 8)
    }

    @ViewBuilder
    private func legend() -> some View {
        let rows = AppStats.rows(for: shots.filter { $0.date >= from && $0.date <= to })
        if !rows.isEmpty {
            HStack(spacing: 12) {
                ForEach(rows.prefix(6), id: \.app) { r in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(AppActivityBarModel.color(for: r.app))
                            .frame(width: 8, height: 8)
                        Text("\(r.app) \(r.count)")
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
        }
    }
}

// MARK: - Pure model (unit-testable, no SwiftUI)

/// Segment math + stable app colours. Pure functions so tests cover them.
enum AppActivityBarModel {
    struct Segment: Identifiable {
        /// Content-based identity (NOT a fresh UUID): the bar recomputes
        /// segments on every hover move, and unstable ids would rebuild
        /// every segment view under the cursor and flicker the popup.
        let id: String
        let app: String
        let start: Date
        let end: Date
        let shots: [ShotStore.Shot]
    }

    /// Shots closer than this belong to one continuous session.
    static let sessionGap: TimeInterval = 5 * 60

    /// A sleep/idle stretch with no shots. Shorter than `idleGap` is just
    /// the normal capture cadence (or a skipped duplicate frame), not rest.
    struct Idle {
        let start: Date
        let end: Date
        var minutes: Int { Int(round(end.timeIntervalSince(start) / 60)) }
    }

    static let idleGap: TimeInterval = 3 * 60

    /// Idle intervals in the window: leading edge, gaps between shots, and
    /// trailing edge — each longer than `idleGap`.
    static func idles(shots: [ShotStore.Shot], from: Date, to: Date) -> [Idle] {
        let sorted = shots
            .filter { $0.date >= from && $0.date <= to }
            .sorted { $0.date < $1.date }
        var out: [Idle] = []
        var prev = from
        for s in sorted {
            if s.date.timeIntervalSince(prev) > idleGap {
                out.append(Idle(start: prev, end: s.date))
            }
            prev = s.date
        }
        if to.timeIntervalSince(prev) > idleGap {
            out.append(Idle(start: prev, end: to))
        }
        return out
    }

    /// Group in-window shots into contiguous same-app segments.
    static func segments(shots: [ShotStore.Shot], from: Date, to: Date) -> [Segment] {
        let sorted = shots
            .filter { $0.date >= from && $0.date <= to }
            .sorted { $0.date < $1.date }
        var out: [Segment] = []
        var cur: [ShotStore.Shot] = []
        for s in sorted {
            if let last = cur.last,
               (last.app ?? "") != (s.app ?? "")
               || s.date.timeIntervalSince(last.date) > sessionGap {
                out.append(finish(cur, from: from, to: to))
                cur = []
            }
            cur.append(s)
        }
        if !cur.isEmpty { out.append(finish(cur, from: from, to: to)) }
        return out
    }

    private static func finish(_ group: [ShotStore.Shot], from: Date, to: Date) -> Segment {
        let first = group.first!.date, last = group.last!.date
        let app = group.first!.app ?? AppStats.unknownApp
        return Segment(
            id: "\(app)-\(first.timeIntervalSince1970)-\(last.timeIntervalSince1970)",
            app: app,
            start: max(from, first.addingTimeInterval(-sessionGap / 2)),
            end: min(to, last.addingTimeInterval(sessionGap / 2)),
            shots: group)
    }

    /// Stable hue per app name (FNV-1a hash → [0, 1)). Same app,
    /// same colour, across launches and windows. Split out from
    /// `color(for:)` so tests can compare hues (`Color` is not Equatable).
    static func hue(for app: String) -> Double {
        var h: UInt64 = 146959
        for b in app.utf8 {
            h ^= UInt64(b)
            h = h &* 1099511628211
        }
        return Double(h % 360) / 360.0
    }

    static func color(for app: String) -> Color {
        Color(hue: hue(for: app), saturation: 0.55, brightness: 0.85)
    }

    // MARK: Positions

    static func x(_ d: Date, from: Date, to: Date, width: CGFloat) -> CGFloat {
        let span = max(1, to.timeIntervalSince(from))
        let f = min(1, max(0, d.timeIntervalSince(from) / span))
        return CGFloat(f) * width
    }

    static func date(at px: CGFloat, from: Date, to: Date, width: CGFloat) -> Date {
        let span = max(1, to.timeIntervalSince(from))
        return from.addingTimeInterval(min(1, max(0, px / max(1, width))) * span)
    }

    // MARK: Ticks + labels

    /// ≤ 8 hour ticks inside the window.
    static func ticks(from: Date, to: Date) -> [Date] {
        let spanH = max(1, to.timeIntervalSince(from) / 3600)
        let stepH = [1, 2, 3, 6, 12, 24].first(where: { spanH / Double($0) <= 8 }) ?? 24
        var out: [Date] = []
        var t = Calendar.current.date(
            bySetting: .minute, value: 0, of: from) ?? from
        if t < from {
            t = Calendar.current.date(byAdding: .hour, value: stepH, to: t) ?? from
        }
        while t <= to {
            out.append(t)
            t = Calendar.current.date(byAdding: .hour, value: stepH, to: t) ?? to.addingTimeInterval(1)
            if out.count > 24 { break }
        }
        return out
    }

    static func tickLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

// MARK: - macOS 13-safe mouse tracking overlay

/// Transparent NSView reporting mouse-move (top-left origin, like SwiftUI)
/// and mouse-down. Needed because the hover-location SwiftUI API
/// (`onContinuousHover`) requires a newer macOS than this app targets.
private struct MouseTracker: NSViewRepresentable {
    var onMove: (CGPoint?) -> Void
    var onClick: (CGPoint) -> Void
    var onDrag: (CGPoint) -> Void
    var onRelease: (CGPoint) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let v = TrackingView()
        v.onMove = onMove
        v.onClick = onClick
        v.onDrag = onDrag
        v.onRelease = onRelease
        return v
    }

    func updateNSView(_ v: TrackingView, context: Context) {
        v.onMove = onMove
        v.onClick = onClick
        v.onDrag = onDrag
        v.onRelease = onRelease
    }

    final class TrackingView: NSView {
        var onMove: ((CGPoint?) -> Void)?
        var onClick: ((CGPoint) -> Void)?
        var onDrag: ((CGPoint) -> Void)?
        var onRelease: ((CGPoint) -> Void)?

        override var isFlipped: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self, userInfo: nil))
        }

        override func mouseMoved(with event: NSEvent) {
            onMove?(convert(event.locationInWindow, from: nil))
        }

        override func mouseExited(with event: NSEvent) {
            onMove?(nil)
        }

        override func mouseDown(with event: NSEvent) {
            onClick?(convert(event.locationInWindow, from: nil))
        }

        override func mouseDragged(with event: NSEvent) {
            onDrag?(convert(event.locationInWindow, from: nil))
        }

        override func mouseUp(with event: NSEvent) {
            onRelease?(convert(event.locationInWindow, from: nil))
        }
    }
}
