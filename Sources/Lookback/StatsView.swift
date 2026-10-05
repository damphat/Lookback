import SwiftUI

/// Window root: Timeline tab + app usage tab, both scoped to one shared
/// `TimeScope` chosen in the sidebar (so "6 giờ qua" scopes stats too).
struct MainView: View {
    @EnvironmentObject var cap: CaptureService
    @StateObject private var scope = TimeScope()

    var body: some View {
        TabView {
            TimelineView()
                .environmentObject(scope)
                .tabItem { Label("Timeline", systemImage: "clock") }
            StatsView()
                .environmentObject(scope)
                .tabItem { Label("Thống kê", systemImage: "chart.bar") }
        }
        .frame(minWidth: 640, minHeight: 520)
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
            HStack {
                Text(scope.preset.rawValue)
                    .font(.headline)
                Spacer()
                Text(total > 0
                     ? "\(TimeText.long(total)) hoạt động"
                     : "Máy nghỉ cả khung này")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
                .listStyle(.inset)
            }
        }
        .padding(14)
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            reload()
        }
    }

    private func reload() {
        shots = ShotStore.list()
    }
}
