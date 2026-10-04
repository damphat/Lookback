import CoreGraphics
import SwiftUI

/// Timeline viewer: image + activity strip (48 thumbnail cells = 24h) + slider.
struct TimelineView: View {
    @EnvironmentObject var cap: CaptureService
    @State private var shots: [ShotStore.Shot] = []
    @State private var fraction: Double = 1.0   // 0 = 24h ago, 1 = now
    @State private var image: NSImage?
    @State private var caption = ""
    @State private var isEmpty = false

    private let span: TimeInterval = 24 * 3600
    private let cells = 48

    var body: some View {
        VStack(spacing: 10) {
            // Permission banner (no auto-prompt: the OS dialog appears
            // ONLY when the user taps "Cấp quyền").
            if !cap.permissionGranted {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Chưa có quyền Screen Recording nên chưa chụp được ảnh.")
                        .font(.callout)
                    Spacer()
                    Button("Cấp quyền…") { cap.requestPermission() }
                    Button("Kiểm tra lại") { cap.refreshPermission(); reload() }
                }
                .padding(8)
                .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            // A. Image (grows with window, fullscreen-capable)
            ZStack(alignment: .bottomLeading) {
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
                if image != nil {
                    Text(caption)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(8)
                }
            }
            .frame(minHeight: 300)

            // B. Activity strip: fixed-width thumbnail cells, aligned with slider.
            GeometryReader { geo in
                let w = (geo.size.width - CGFloat(cells - 1) * 2) / CGFloat(cells)
                HStack(spacing: 2) {
                    ForEach(0..<cells, id: \.self) { i in
                        cellView(i, width: w)
                            .frame(width: w, height: 28)
                            .onTapGesture { fraction = Double(i) / Double(cells - 1); refresh() }
                            .help(timeLabel(for: cellStart(i)))
                    }
                }
            }
            .frame(height: 28)

            // C. Slider full width, labels below so both ends align with the strip.
            VStack(spacing: 2) {
                Slider(value: $fraction, in: 0...1).onChange(of: fraction) { _ in refresh() }
                HStack {
                    Text("−24h").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(relativeLabel()).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("bây giờ").font(.caption).foregroundStyle(.secondary)
                }
            }

            // D. One slim status line (was 3 rows of buttons).
            HStack {
                Circle()
                    .fill(cap.paused ? .orange : (cap.permissionGranted ? .green : .red))
                    .frame(width: 8, height: 8)
                Text(cap.status).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(minWidth: 640, minHeight: 520)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    cap.paused.toggle()
                } label: {
                    Label(cap.paused ? "Tiếp tục" : "Tạm dừng",
                          systemImage: cap.paused ? "play.fill" : "pause.fill")
                }
                .help("Tạm dừng / tiếp tục chụp màn hình")
                Menu {
                    Button("Mở thư mục ảnh") { NSWorkspace.shared.open(ShotStore.dir) }
                    Button("Làm mới") { cap.refreshPermission(); reload() }
                } label: {
                    Label("Thêm", systemImage: "ellipsis.circle")
                }
            }
        }
        .onAppear { reload(); cap.start() }
    }

    // MARK: - Cells

    private func cellStart(_ i: Int) -> Date {
        Date().addingTimeInterval(-span + Double(i) * span / Double(cells))
    }

    private func repShot(_ i: Int) -> ShotStore.Shot? {
        let mid = cellStart(i).addingTimeInterval(span / Double(cells) / 2)
        return ShotStore.nearest(to: mid, in: shots, tolerance: span / Double(cells) / 2)
    }

    @ViewBuilder
    private func cellView(_ i: Int, width w: CGFloat) -> some View {
        let isActive = Int(round(fraction * Double(cells - 1))) == i
        // Explicit content size + clipped: the image can never bleed
        // into neighbouring cells regardless of its aspect ratio.
        Group {
            if let s = repShot(i), let t = ThumbCache.thumb(for: s) {
                Image(nsImage: t)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: 28)
                    .clipped()
            } else {
                Color(nsColor: .separatorColor).opacity(0.5)
                    .frame(width: w, height: 28)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(isActive ? Color.accentColor : .clear, lineWidth: 2)
        )
    }

    // MARK: - Helpers

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

    private func relativeLabel() -> String {
        let mins = Int(round((1.0 - fraction) * span / 60))
        if mins < 1 { return "hiện tại" }
        if mins < 60 { return "\(mins) phút trước" }
        return "\(mins / 60)h\(mins % 60 == 0 ? "" : "\(mins % 60)p") trước"
    }

    private func timeLabel(for d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
}
