import CoreGraphics
import SwiftUI

/// Timeline viewer with sidebar: time presets + capture settings on the left,
/// image + activity bar (the single scrubber) on the right.
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

    private var window: (Date, Date) { (scope.from, scope.to) }
    /// Built once per body from cached shots + fixed preset window.
    private var activity: ActivityState {
        ActivityState(samples: shots, from: window.0, to: window.1)
    }
    private var regions: [ActivityState.Region] { activity.regions() }
    private var activeMinutes: Int {
        regions.filter { !$0.isSleep }.reduce(0) { $0 + $1.minutes }
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar: time presets + capture settings.
            List(selection: $scope.preset) {
                Section("Khung giờ") {
                    ForEach(TimeScope.Preset.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                Section("Ghi hình") {
                    Toggle("Tạm dừng chụp", isOn: $cap.paused)
                    Button("Mở thư mục ảnh") { NSWorkspace.shared.open(ShotStore.dir) }
                    Text("\(TimeText.long(activeMinutes)) hoạt động trong khung này")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Lookback")
            .navigationSplitViewColumnWidth(min: 150, ideal: 175, max: 230)
        } detail: {
            VStack(spacing: 10) {
                if !cap.permissionGranted {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                        Text("Chưa có quyền Screen Recording nên chưa chụp được ảnh.")
                            .font(.callout).lineLimit(2).truncationMode(.tail)
                        Spacer(minLength: 4)
                        Button("Cấp quyền…") { cap.requestPermission() }
                            .controlSize(.small)
                        Button("Kiểm tra lại") { cap.refreshPermission(); reload() }
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
                        Text("Chrome đang mở nhưng Lookback bị từ chối Automation nên không lấy được tên website.")
                            .font(.callout).lineLimit(2).truncationMode(.tail)
                        Spacer(minLength: 4)
                        Button("Cấp quyền…") { cap.requestAutomation() }
                            .controlSize(.small)
                        Button("Mở Settings…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .lineLimit(2)
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay {
                            if let image {
                                Image(nsImage: image)
                                    .resizable().aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            } else {
                                VStack(spacing: 6) {
                                    Image(systemName: "moon.zzz").font(.largeTitle).foregroundStyle(.secondary)
                                    Text(isEmpty ? caption : "Đang tải…").foregroundStyle(.secondary)
                                }
                            }
                        }
                }
                .frame(minHeight: 300)

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
            .padding(14)
        }
        .frame(minWidth: 640, minHeight: 520)
        .onAppear { scope.refreshWindow(); reload(); cap.start() }
        .onChange(of: scope.preset) { _ in scope.refreshWindow(); reload(keepPosition: true); clampSelection(); refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            reload(keepPosition: true)
        }
    }

    // MARK: - Helpers

    private func clampSelection() {
        let (from, to) = window
        selectedDate = min(max(selectedDate, from), to)
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

    private func reload(keepPosition: Bool = false) {
        let (from, to) = window
        let all = ShotStore.list()
        shots = all.filter { $0.date >= from && $0.date <= to }
        if shots.isEmpty {
            image = nil
            caption = "Chưa có hoạt động nào trong khung này."
            isEmpty = true
        } else {
            if !keepPosition { selectedDate = to }
            clampSelection()
            refresh()
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
