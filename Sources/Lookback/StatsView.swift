import SwiftUI

/// Per-day usage stats, level 1 = app (sorted by shot count ~ minutes used),
/// level 2 = detail breakdown (website / project folder) where available.
struct AppStats {
    struct Row {
        let app: String
        let count: Int
        /// (detail, count) sorted desc. Empty when shots carry no detail.
        let details: [(String, Int)]
    }

    static let unknownApp = "Không rõ app"

    /// Group today's shots by app, each row's details by part 3.
    static func rows(for shots: [ShotStore.Shot], day: Date = Date()) -> [Row] {
        let cal = Calendar.current
        let today = shots.filter { cal.isDate($0.date, inSameDayAs: day) }
        let byApp = Dictionary(grouping: today) { $0.app ?? unknownApp }
        return byApp.map { app, ss in
            let det = Dictionary(grouping: ss.compactMap(\.detail)) { $0 }
                .map { ($0.key, $0.value.count) }
                .sorted { $0.1 > $1.1 }
            return Row(app: app, count: ss.count, details: det)
        }
        .sorted { $0.count > $1.count }
    }
}

/// Window root: Timeline tab + per-day app usage tab.
struct MainView: View {
    @EnvironmentObject var cap: CaptureService

    var body: some View {
        TabView {
            TimelineView()
                .tabItem { Label("Timeline", systemImage: "clock") }
            StatsView()
                .tabItem { Label("Thống kê", systemImage: "chart.bar") }
        }
        .frame(minWidth: 640, minHeight: 520)
    }
}

struct StatsView: View {
    @EnvironmentObject var cap: CaptureService
    @State private var shots: [ShotStore.Shot] = []

    var body: some View {
        let rows = AppStats.rows(for: shots)
        let total = rows.reduce(0) { $0 + $1.count }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Hôm nay")
                    .font(.headline)
                Spacer()
                Text(total > 0
                     ? "\(total) ảnh ≈ \(total) phút dùng máy"
                     : "Chưa có ảnh nào hôm nay")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if rows.isEmpty {
                Spacer()
                HStack { Spacer(); Text("Máy nghỉ cả ngày?").foregroundStyle(.secondary); Spacer() }
                Spacer()
            } else {
                List {
                    ForEach(rows, id: \.app) { row in
                        if row.details.isEmpty {
                            HStack {
                                Text(row.app)
                                Spacer()
                                Text("\(row.count) ảnh")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            DisclosureGroup {
                                ForEach(row.details, id: \.0) { d, c in
                                    HStack {
                                        Text(d).font(.callout)
                                        Spacer()
                                        Text("\(c) ảnh")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(row.app)
                                    Spacer()
                                    Text("\(row.count) ảnh")
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
