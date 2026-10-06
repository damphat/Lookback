import AppKit
import SwiftUI

/// The activity bar IS the scrubber. One cached `ActivityState` + precomputed
/// regions flow in from the parent (built once per window/reload); hover and
/// drag only do lookups against them — no re-derivation per pixel.
///
/// Single-truth rule: everything shown (region colours, hover card, viewer
/// image, status line) derives from `state.view(at:in:)`. No caller applies
/// its own shot tolerance, so bar and viewer can never disagree.
struct AppActivityBar: View {
    let state: ActivityState
    let regions: [ActivityState.Region]
    let shots: [ShotStore.Shot]
    @Binding var selectedDate: Date
    var onScrub: (Date) -> Void = { _ in }

    @State private var hoverX: CGFloat? = nil
    @State private var hoverThumb: NSImage? = nil
    @State private var hoverShotDate: Date? = nil
    @State private var lastWidth: CGFloat? = nil
    @State private var dragging = false

    private let barHeight: CGFloat = 34
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let w = max(1, geo.size.width)
                ZStack(alignment: .bottomLeading) {
                    // Single-pass draw: track + regions + children + labels.
                    // (The time axis lives in TimeRuler below, not here.)
                    Canvas { ctx, size in
                        let h = barHeight
                        ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: size.width, height: h),
                                                     cornerRadius: 7),
                                 with: .color(Color(nsColor: .separatorColor).opacity(0.35)))
                        for r in regions {
                            let x0 = frac(r.start) * size.width
                            let rw = max(3, frac(r.end) * size.width - x0)
                            let rect = CGRect(x: x0, y: 0, width: rw, height: h)
                            if r.isSleep {
                                ctx.fill(Path(roundedRect: rect, cornerRadius: 5),
                                         with: .color(Color(nsColor: .separatorColor).opacity(isHovered(r) ? 0.7 : 0.45)))
                            } else {
                                let app = r.kind.appName ?? "?"
                                ctx.fill(Path(roundedRect: rect, cornerRadius: 5),
                                         with: .color(AppPalette.color(for: app).opacity(isHovered(r) ? 1.0 : 0.72)))
                                // Level-2: slim sibling shades of the app colour
                                // (distinct by index, never hash-collided),
                                // inset 1px so neighbours don't touch.
                                for (i, c) in r.children.enumerated() {
                                    let cx = frac(c.start) * size.width
                                    let cw = frac(c.end) * size.width - cx
                                    guard cw > 3 else { continue }
                                    ctx.fill(Path(roundedRect: CGRect(x: cx + 1, y: h * 0.64, width: cw - 2, height: h * 0.32), cornerRadius: 2),
                                             with: .color(AppPalette.shade(app: app, index: i)))
                                }
                            }
                            // One overlay path for every region kind: sleep cells
                            // get their duration too, so a future render change
                            // (border, style) touches this spot only.
                            drawCellLabel(minutes: r.minutes, in: rect, ctx: &ctx)
                            if isHovered(r) {
                                ctx.stroke(Path(roundedRect: rect, cornerRadius: 5),
                                           with: .color(.white.opacity(0.85)), lineWidth: 1.5)
                            }
                        }
                    }
                    .frame(height: barHeight)
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: barHeight + 6)
                        .offset(x: frac(selectedDate) * w - 1)
                    // ONE full-bar mouse layer: uniform behaviour everywhere.
                    MouseTracker(
                        onMove: { loc in setHover(loc?.x, width: w) },
                        onClick: { loc in scrub(to: loc.x, width: w) },
                        onDrag: { loc in scrub(to: loc.x, width: w) },
                        onRelease: { _ in dragging = false }
                    )
                }
                .frame(height: barHeight)
                .overlay(alignment: .bottomLeading) {
                    if let hx = hoverX ?? (dragging ? frac(selectedDate) * w : nil) {
                        hoverCard(at: date(at: hx, width: w))
                            .offset(x: popupX(hx, width: w), y: -(barHeight + 8))
                            .allowsHitTesting(false)
                    }
                }
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() }
                    else { NSCursor.pop(); hoverX = nil; hoverThumb = nil; hoverShotDate = nil }
                }
            }
            .frame(height: barHeight)
            TimeRuler(from: state.from, to: state.to)
        }
    }

    /// Duration only (users learn apps by colour): small type centred on the
    /// cell's top half so it shows even on narrow cells. No room → no label.
    private func drawCellLabel(minutes: Int, in rect: CGRect, ctx: inout GraphicsContext) {
        guard rect.width >= 40 else { return }
        ctx.draw(Text(TimeText.short(minutes)).font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.92)),
                 at: CGPoint(x: rect.midX, y: rect.minY + barHeight * 0.26), anchor: .center)
    }

    // MARK: - Cached lookups (no state rebuild)

    private func frac(_ d: Date) -> CGFloat {
        let span = max(1, state.to.timeIntervalSince(state.from))
        return CGFloat(min(1, max(0, d.timeIntervalSince(state.from) / span)))
    }

    private func date(at px: CGFloat, width w: CGFloat) -> Date {
        state.from.addingTimeInterval(min(1, max(0, px / w)) * max(1, state.to.timeIntervalSince(state.from)))
    }

    private func isHovered(_ r: ActivityState.Region) -> Bool {
        guard let hx = hoverX, let w = lastWidth else { return false }
        let t = date(at: hx, width: w)
        return r.start <= t && t <= r.end
    }

    private func setHover(_ px: CGFloat?, width w: CGFloat) {
        lastWidth = w
        hoverX = px
        guard let hx = px else { hoverThumb = nil; hoverShotDate = nil; return }
        // Prefetch the thumbnail for the single-truth shot at this pixel.
        // Guarded by date so re-hovers of the same shot skip the decode.
        if case .app(let s, _) = state.view(at: date(at: hx, width: w), in: regions) {
            if hoverShotDate != s.date {
                hoverShotDate = s.date
                hoverThumb = shots.first(where: { $0.date == s.date })
                    .flatMap { ThumbCache.thumb(for: $0, width: 220) }
            }
        } else {
            hoverShotDate = nil
            hoverThumb = nil
        }
    }

    /// Uniform scrub: every pixel maps to a timestamp, always moves playhead.
    private func scrub(to px: CGFloat, width w: CGFloat) {
        dragging = true
        lastWidth = w
        hoverX = px
        let t = date(at: px, width: w)
        selectedDate = t
        onScrub(t)
        setHover(px, width: w)
    }

    private func popupX(_ hx: CGFloat, width w: CGFloat) -> CGFloat {
        let cardW: CGFloat = 236
        return min(max(hx - cardW / 2, 0), max(0, w - cardW))
    }

    /// One layout for every region kind: title row (marker + name + ONE
    /// duration, headline-strong), range row, children, thumbnail, footer.
    /// Sleep uses the same slots — nothing to hunt for, no branch UI.
    private func hoverCard(at t: Date) -> some View {
        let verdict = state.view(at: t, in: regions)
        return VStack(alignment: .leading, spacing: 6) {
            switch verdict {
            case .sleep(let r):
                cardTitle(marker: .sleep, title: "Máy nghỉ", minutes: r?.minutes)
                if let r {
                    cardRange(from: r.start, to: r.end)
                }
            case .app(_, let r):
                let app = r.kind.appName ?? "?"
                cardTitle(marker: .app(app), title: app, minutes: r.minutes)
                cardRange(from: r.start, to: r.end)
                ForEach(Array(r.topDetails().enumerated()), id: \.element.detail) { i, c in
                    HStack(spacing: 6) {
                        Circle().fill(AppPalette.shade(app: app, index: i)).frame(width: 8, height: 8)
                        Text(c.detail).font(.caption).lineLimit(1)
                        Spacer()
                        Text(TimeText.short(c.minutes)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let img = hoverThumb {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            case .empty:
                cardTitle(marker: .none, title: "Ngoài khung giờ", minutes: nil)
            }
            Text(Self.timeFmt.string(from: t))
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(10)
        .frame(width: 236, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 8)
    }

    private enum CardMarker {
        case app(String)
        case sleep
        case none
    }

    /// Shared title row: marker + name left, the ONE duration right, strong.
    private func cardTitle(marker: CardMarker, title: String, minutes: Int?) -> some View {
        HStack(spacing: 6) {
            switch marker {
            case .app(let app):
                Circle().fill(AppPalette.color(for: app)).frame(width: 10, height: 10)
            case .sleep:
                Image(systemName: "moon.zzz").foregroundStyle(.secondary)
            case .none:
                EmptyView()
            }
            Text(title).font(.headline).lineLimit(1)
            Spacer()
            if let minutes {
                Text(TimeText.long(minutes)).font(.headline)
            }
        }
    }

    private func cardRange(from: Date, to: Date) -> some View {
        Text("\(Self.timeFmt.string(from: from)) → \(Self.timeFmt.string(from: to))")
            .font(.caption).foregroundStyle(.secondary)
    }
}

private struct MouseTracker: NSViewRepresentable {
    var onMove: (CGPoint?) -> Void
    var onClick: (CGPoint) -> Void
    var onDrag: (CGPoint) -> Void
    var onRelease: (CGPoint) -> Void
    func makeNSView(context: Context) -> TrackingView {
        let v = TrackingView()
        v.onMove = onMove; v.onClick = onClick; v.onDrag = onDrag; v.onRelease = onRelease
        return v
    }
    func updateNSView(_ v: TrackingView, context: Context) {
        v.onMove = onMove; v.onClick = onClick; v.onDrag = onDrag; v.onRelease = onRelease
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
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        }
        override func mouseMoved(with event: NSEvent) { onMove?(convert(event.locationInWindow, from: nil)) }
        override func mouseExited(with event: NSEvent) { onMove?(nil) }
        override func mouseDown(with event: NSEvent) { onMove?(convert(event.locationInWindow, from: nil)); onClick?(convert(event.locationInWindow, from: nil)) }
        override func mouseDragged(with event: NSEvent) { onDrag?(convert(event.locationInWindow, from: nil)) }
        override func mouseUp(with event: NSEvent) { onRelease?(convert(event.locationInWindow, from: nil)) }
    }
}
