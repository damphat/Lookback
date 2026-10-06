import CoreGraphics
import SwiftUI

/// Timeline viewer (center column): photo + readout + activity bar (the
/// single scrubber). No chrome of its own — presets live in the left sidebar,
/// stats in the right inspector.
///
/// Perf contract: `ActivityState` + regions are built ONCE per (reload, view
/// preset) and passed into the bar. Hover/drag inside the bar never rebuilds
/// them — only O(log n) lookups + one cached thumbnail.
struct TimelineView: View {
    @EnvironmentObject var cap: CaptureService
    @EnvironmentObject var scope: TimeScope
    @State private var shots: [ShotStore.Shot] = []
    @State private var selectedDate = Date()
    @State private var image: NSImage?
    @State private var caption = ""
    @State private var isEmpty = false
    @State private var imageTask: Task<Void, Never>?
    /// Window edge rides "now" on trailing presets; 30s is plenty (shots
    /// land every 60s) and `tick` skips the write when nothing moved.
    private static let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var window: (Date, Date) { (scope.from, scope.to) }
    /// Built once per body from cached shots + fixed preset window.
    private var activity: ActivityState {
        ActivityState(samples: shots, from: window.0, to: window.1)
    }
    private var regions: [ActivityState.Region] { activity.regions() }

    var body: some View {
        VStack(spacing: 8) {
                if !cap.permissionGranted {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                        Text("Chưa có quyền Screen Recording nên chưa chụp được ảnh.")
                            .font(.callout).lineLimit(2).truncationMode(.tail)
                        Spacer(minLength: 4)
                        Button("Cấp quyền…") { cap.requestPermission() }
                            .controlSize(.small)
                        Button("Kiểm tra lại") { cap.refreshPermission(); rescope() }
                            .controlSize(.small)
                    }
                    .padding(8)
                    .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .lineLimit(2)
                }
                if cap.automationDenied {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.trianglebadge.exclamationmark")
                            .foregroundStyle(.orange)
                        Text("Lookback chưa có quyền Automation nên không lấy được tên website từ Chrome.")
                            .font(.callout).lineLimit(2).truncationMode(.tail)
                        Spacer(minLength: 4)
                        // ONE button: tries the consent dialog, falls back to
                        // Settings when macOS stays silent after a past deny.
                        Button("Cấp quyền…") { cap.fixAutomation(); rescope() }
                            .controlSize(.small)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .lineLimit(2)
                }
                // Single photo well: one flat background, one corner radius —
                // no card-in-card nesting eating horizontal space.
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable().aspectRatio(contentMode: .fit)
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "moon.zzz").font(.largeTitle).foregroundStyle(.secondary)
                            Text(isEmpty ? caption : "Đang tải…").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // The single selected-time readout: big time + context,
                // centred between photo and bar. Replaces the old corner
                // pill and bottom status line (both removed as duplicates).
                VStack(spacing: 0) {
                    Text(timeString(for: selectedDate))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(selectedContext())
                        .font(.callout).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                .frame(maxWidth: .infinity)

                // The bar IS the slider: uniform scrub anywhere.
                AppActivityBar(
                    state: activity,
                    regions: regions,
                    shots: shots,
                    selectedDate: $selectedDate,
                    onScrub: { _ in refresh() }
                )
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { cap.start(); rescope(forceWindow: true) }
        .onChange(of: scope.preset) { _ in rescope(forceWindow: true) }
        .onChange(of: cap.generation) { _ in rescope() }
        .onReceive(Self.ticker) { _ in rescope() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            cap.refreshPermission(); rescope()
        }
    }

    // MARK: - Helpers

    /// THE single rescope: EVERY window change flows here (open, preset,
    /// new shot, 30s tick, window focus, permission tap). Live-pin rule:
    /// selection near `to` means "watching now" → ride the new edge,
    /// otherwise clamp into the window. This replaces the old scatter of
    /// reload(keepPosition:) + clampSelection + refresh call sites.
    private func rescope(forceWindow: Bool = false) {
        let wasLive = TimeScope.isLive(selectedDate, to: scope.to)
        scope.tick(force: forceWindow)
        let (from, to) = window
        shots = ShotStore.list().filter { $0.date >= from && $0.date <= to }
        if shots.isEmpty {
            image = nil
            caption = "Chưa có hoạt động nào trong khung này."
            isEmpty = true
        } else {
            selectedDate = wasLive ? to : min(max(selectedDate, from), to)
            refresh()
        }
    }

    /// Viewer truth = the same `view(at:)` the bar hovers. The viewer never
    /// applies its own tolerance, so it can never report "Máy nghỉ" inside an
    /// app region (or a photo where the card claims none).
    private func viewedShot() -> ShotStore.Shot? {
        if case .app(let s, _) = activity.view(at: selectedDate, in: regions) {
            return shots.first { $0.date == s.date }
        }
        return nil
    }

    /// Image decode hops off the main thread; stale tasks are cancelled so
    /// fast scrubbing never stacks decodes.
    private func refresh() {
        imageTask?.cancel()
        guard case .app(let s, _) = activity.view(at: selectedDate, in: regions),
              let match = shots.first(where: { $0.date == s.date }) else {
            image = nil
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            caption = "Máy nghỉ lúc \(f.string(from: selectedDate))"
            isEmpty = true
            return
        }
        isEmpty = false
        caption = ShotStore.fmt.string(from: match.date).replacingOccurrences(of: "_", with: " ")
        let url = match.url
        imageTask = Task {
            if let img = await Task.detached(priority: .userInitiated) { NSImage(contentsOf: url) }.value {
                if !Task.isCancelled { image = img }
            }
        }
    }

    private func timeString(for d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }

    private func dateString(for d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE, dd/MM/yyyy"; f.locale = Locale(identifier: "vi_VN")
        return f.string(from: d).capitalized
    }

    /// Second line of the selection readout: date + app context + age,
    /// or the sleep state. Time-domain first, no photo counts.
    private func selectedContext() -> String {
        var parts = [dateString(for: selectedDate)]
        if !isEmpty, let s = viewedShot() {
            var ctx: [String] = []
            if let a = s.app { ctx.append(a) }
            if let d = s.detail { ctx.append(d) }
            if !ctx.isEmpty { parts.append(ctx.joined(separator: " • ")) }
        } else {
            parts.append("Máy nghỉ")
        }
        parts.append(relativeLabel())
        return parts.joined(separator: " • ")
    }

    private func relativeLabel() -> String {
        TimeText.ago(Int(round(Date().timeIntervalSince(selectedDate) / 60)))
    }
}
