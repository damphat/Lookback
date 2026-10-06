import SwiftUI

/// Window root: 3-column layout sharing one `TimeScope`.
///
/// - Left sidebar (collapsible): time presets + capture options.
/// - Center: the timeline viewer (photo + scrub bar).
/// - Right inspector (collapsible): "Thống kê" for the same window, so the
///   numbers always match the bar — no more Timeline/Thống kê tab switch.
struct MainView: View {
    @EnvironmentObject var cap: CaptureService
    @StateObject private var scope = TimeScope()
    /// Native 2-column split only toggles as a whole (all/detailOnly), so the
    /// left sidebar uses it while the right inspector is a plain collapsible
    /// panel — both toggles stay independent.
    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var showInspector = true

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            OptionsSidebar()
                .navigationSplitViewColumnWidth(min: 160, ideal: 185, max: 225)
        } detail: {
            HStack(spacing: 0) {
                TimelineView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showInspector {
                    Divider()
                    StatsView()
                        .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
                }
            }
        }
        .environmentObject(scope)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    visibility = visibility == .detailOnly ? .all : .detailOnly
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Ẩn/hiện tùy chọn")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Ẩn/hiện thống kê")
            }
        }
        .frame(minWidth: 920, minHeight: 580)
    }
}

/// Left sidebar: time presets + capture options. Read-only status; the only
/// start/stop lives in the tray menu.
struct OptionsSidebar: View {
    @EnvironmentObject var cap: CaptureService
    @EnvironmentObject var scope: TimeScope

    var body: some View {
        List(selection: $scope.preset) {
            Section("Khung giờ") {
                ForEach(TimeScope.Preset.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            Section("Tùy chọn") {
                // Pause lives ONLY in the tray menu (single start/stop);
                // the window shows the state read-only, no second switch.
                if cap.paused {
                    Label("Đang tạm dừng chụp", systemImage: "pause.circle")
                        .foregroundStyle(.secondary)
                }
                Button("Mở thư mục ảnh") { NSWorkspace.shared.open(ShotStore.dir) }
            }
        }
        .listStyle(.sidebar)
    }
}

struct StatsView: View {
    @EnvironmentObject var cap: CaptureService
    @EnvironmentObject var scope: TimeScope
    @State private var shots: [ShotStore.Shot] = []

    /// Time-domain stats: same regions the bar draws, so the numbers match.
    private var rows: [ActivityState.SummaryRow] {
        ActivityState(samples: shots, from: scope.from, to: scope.to).summary()
    }

    var body: some View {
        let total = rows.reduce(0) { $0 + $1.minutes }
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Thống kê")
                    .font(.headline)
                Text(total > 0
                     ? "\(TimeText.long(total)) hoạt động • \(scope.preset.rawValue.lowercased())"
                     : "Máy nghỉ cả khung này")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            if rows.isEmpty {
                Spacer()
                HStack { Spacer(); Text("Máy nghỉ cả khung này?").foregroundStyle(.secondary); Spacer() }
                Spacer()
            } else {
                List {
                    ForEach(rows, id: \.app) { row in
                        if row.details.isEmpty {
                            HStack {
                                Text(row.app)
                                Spacer()
                                Text(TimeText.short(row.minutes))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            DisclosureGroup {
                                ForEach(row.details, id: \.0) { d, m in
                                    HStack {
                                        Text(d).font(.callout)
                                        Spacer()
                                        Text(TimeText.short(m))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(row.app)
                                    Spacer()
                                    Text(TimeText.short(row.minutes))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear { reload() }
        .onReceive(cap.$generation) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            reload()
        }
    }

    private func reload() {
        shots = ShotStore.list()
    }
}
