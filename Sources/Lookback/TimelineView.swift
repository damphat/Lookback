import CoreGraphics
import SwiftUI

/// Timeline viewer: image + activity strip (48 cells = 24h) + slider.
struct TimelineView: View {
    @EnvironmentObject var cap: CaptureService
    @State private var shots: [ShotStore.Shot] = []
    @State private var fraction: Double = 1.0   // 0 = 24h ago, 1 = now
    @State private var image: NSImage?
    @State private var caption = ""
    @State private var isEmpty = false

    private let span: TimeInterval = 24 * 3600

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .frame(height: 360)
                    .overlay {
                        if let image {
                            Image(nsImage: image)
                                .resizable().aspectRatio(contentMode: .fit)
                                .frame(height: 360).clipShape(RoundedRectangle(cornerRadius: 10))
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: "moon.zzz").font(.largeTitle).foregroundStyle(.secondary)
                                Text(isEmpty ? caption : "Đang tải…").foregroundStyle(.secondary)
                            }.frame(height: 360)
                        }
                    }
                if image != nil {
                    Text(caption)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                }
            }

            // Activity strip: 48 cells, each = 30 min. Bright = has shots.
            HStack(spacing: 2) {
                ForEach(0..<48, id: \.self) { i in
                    let cellStart = Date().addingTimeInterval(-span + Double(i) * 1800)
                    let has = shots.contains { abs($0.date.timeIntervalSince(cellStart.addingTimeInterval(900))) < 900 }
                    RoundedRectangle(cornerRadius: 2)
                        .fill(has ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.5))
                        .frame(height: 14)
                        .onTapGesture {
                            fraction = Double(i) / 47.0
                            refresh()
                        }
                        .help(timeLabel(for: cellStart))
                }
            }

            HStack {
                Text("−24h").font(.caption).foregroundStyle(.secondary)
                Slider(value: $fraction, in: 0...1).onChange(of: fraction) { _ in refresh() }
                Text("bây giờ").font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Text(caption).font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button(cap.paused ? "Tiếp tục" : "Tạm dừng") { cap.paused.toggle() }
                Button("Mở thư mục") { NSWorkspace.shared.open(ShotStore.dir) }
                Button("Làm mới") { reload() }
            }
            .font(.callout)
        }
        .padding(14)
        .frame(width: 640)
        .onAppear { reload(); requestPermissionIfNeeded(); cap.start() }
    }

    private func selectedDate() -> Date { Date().addingTimeInterval(-span + fraction * span) }

    private func refresh() {
        let t = selectedDate()
        if let s = ShotStore.nearest(to: t, in: shots) {
            image = NSImage(contentsOf: s.url)
            caption = ShotStore.fmt.string(from: s.date).replacingOccurrences(of: "_", with: " ")
            isEmpty = false
        } else {
            image = nil
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            caption = "Máy nghỉ / không có ảnh lúc \(f.string(from: t))"
            isEmpty = true
        }
    }

    private func reload() {
        shots = ShotStore.list().filter { $0.date > Date().addingTimeInterval(-span) }
        if shots.isEmpty { image = nil; caption = "Chưa có ảnh nào — app sẽ chụp mỗi phút khi bạn dùng máy."; isEmpty = true }
        else { fraction = 1.0; refresh() }
    }

    private func timeLabel(for d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }

    private func requestPermissionIfNeeded() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }
}
