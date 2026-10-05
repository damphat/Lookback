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
                    // Single-pass draw: track + all regions + children + ticks.
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
                                if case .app(let app) = r.kind {
                                    ctx.fill(Path(roundedRect: rect, cornerRadius: 5),
                                             with: .color(AppActivityBarModel.color(for: app).opacity(isHovered(r) ? 1.0 : 0.72)))
                                }
                                // Level-2: shorter inner blocks, one distinct
                                // colour per detail, tiling edge-to-edge.
                                for c in r.children {
                                    let cx = frac(c.start) * size.width
                                    let cw = max(2, frac(c.end) * size.width - cx)
                                    ctx.fill(Path(roundedRect: CGRect(x: cx, y: h * 0.52, width: cw, height: h * 0.48), cornerRadius: 3),
                                             with: .color(AppActivityBarModel.color(for: c.detail)))
                                }
                            }
                            if isHovered(r) {
                                ctx.stroke(Path(roundedRect: rect, cornerRadius: 5),
                                           with: .color(.white.opacity(0.85)), lineWidth: 1.5)
                            }
                        }
                        for t in AppActivityBarModel.ticks(from: state.from, to: state.to) {
                            let x = frac(t) * size.width
                            ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: h)),
                                     with: .color(Color(nsColor: .separatorColor)))
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
            HStack {
                Text(Self.timeFmt.string(from: state.from)); Spacer()
                Text(Self.timeFmt.string(from: Date(timeIntervalSince1970: (state.from.timeIntervalSince1970 + state.to.timeIntervalSince1970) / 2)))
                Spacer()
                Text(abs(state.to.timeIntervalSinceNow) < 300 ? "bây giờ" : Self.timeFmt.string(from: state.to))
            }
            .font(.caption).foregroundStyle(.secondary)
        }
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

    /// Hover card reads the SAME `view(at:)` as the viewer: an app verdict
    /// always carries its shot + thumbnail line, so the card can never claim
    /// "no photo" where a click shows one (or vice versa).
    private func hoverCard(at t: Date) -> some View {
        let verdict = state.view(at: t, in: regions)
        return VStack(alignment: .leading, spacing: 6) {
            switch verdict {
            case .sleep(let r):
                HStack(spacing: 8) {
                    Image(systemName: "moon.zzz").font(.title3).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Máy nghỉ").font(.headline)
                        if let r {
                            Text("\(Self.timeFmt.string(from: r.start)) → \(Self.timeFmt.string(from: r.end)) • \(r.minutes) phút • 0 ảnh")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Ngoài khung giờ • 0 ảnh").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            case .app(let s, let r):
                HStack(spacing: 6) {
                    if case .app(let app) = r.kind {
                        Circle().fill(AppActivityBarModel.color(for: app)).frame(width: 10, height: 10)
                        Text(app).font(.headline).lineLimit(1)
                    }
                    Spacer()
                    Text("\(r.count) ảnh").font(.caption).foregroundStyle(.secondary)
                }
                Text("\(Self.timeFmt.string(from: r.start)) → \(Self.timeFmt.string(from: r.end)) • \(r.minutes) phút")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(r.children.prefix(5), id: \.detail) { c in
                    HStack(spacing: 6) {
                        Circle().fill(AppActivityBarModel.color(for: c.detail)).frame(width: 8, height: 8)
                        Text(c.detail).font(.caption).lineLimit(1)
                        Spacer()
                        Text("\(c.count) ảnh").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let img = hoverThumb {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Text("Ảnh lúc \(Self.timeFmt.string(from: s.date)) — bấm để xem")
                    .font(.caption).foregroundStyle(.secondary)
            case .empty:
                Text("Ngoài khung giờ • 0 ảnh").font(.caption).foregroundStyle(.secondary)
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
}

// MARK: - Geometry helpers (view math only; rules live in ActivityState)

enum AppActivityBarModel {
    static func hue(for app: String) -> Double { ActivityState.hue(for: app) }
    static func color(for app: String) -> Color {
        Color(hue: hue(for: app), saturation: 0.55, brightness: 0.85)
    }
    static func ticks(from: Date, to: Date) -> [Date] {
        let spanH = max(1, to.timeIntervalSince(from) / 3600)
        let stepH = [1, 2, 3, 6, 12, 24].first(where: { spanH / Double($0) <= 8 }) ?? 24
        var out: [Date] = []
        var t = Calendar.current.date(bySetting: .minute, value: 0, of: from) ?? from
        if t < from { t = Calendar.current.date(byAdding: .hour, value: stepH, to: t) ?? from }
        while t <= to {
            out.append(t)
            t = Calendar.current.date(byAdding: .hour, value: stepH, to: t) ?? to.addingTimeInterval(1)
            if out.count > 24 { break }
        }
        return out
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
