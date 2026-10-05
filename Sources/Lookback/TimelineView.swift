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
    @State private var scrubbing = false

    private let span: TimeInterval = 24 * 3600

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

            // A. Image (grows with window, fullscreen-capable) with big
            // centered time overlay: large time-of-day, small date, relative age.
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
                if scrubbing {
                    // Full overlay only while dragging: big time, small date,
                    // relative age. Dims the photo so text always reads well.
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.black.opacity(image != nil ? 0.25 : 0))
                    VStack(spacing: 2) {
                        Text(dateString(for: selectedDate()))
                            .font(.headline)
                        Text(timeString(for: selectedDate()))
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                        Text(relativeLabel())
                            .font(.subheadline)
                    }
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
                } else {
                    // Idle: one small pill, bottom-left, out of the way.
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(timeString(for: selectedDate())) • \(relativeLabel())")
                                .font(.callout).bold()
                            Text(dateString(for: selectedDate()))
                                .font(.caption)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(10)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            .frame(minHeight: 300)

            // B. Activity bar: per-app colour segments for the observed
            // window, hover popup + click-to-view. Same selection state as
            // the slider below (both drive `fraction`).
            AppActivityBar(
                shots: shots,
                from: Date().addingTimeInterval(-span),
                to: Date(),
                selectedDate: Binding(
                    get: { selectedDate() },
                    set: {
                        fraction = min(1, max(0, ($0.timeIntervalSinceNow + span) / span))
                        refresh()
                    }),
                onSelect: { _ in refresh() }
            )

            // C. Slider full width, labels below so both ends align with the strip.
            VStack(spacing: 2) {
                Slider(value: $fraction, in: 0...1, onEditingChanged: { scrubbing = $0 })
                    .onChange(of: fraction) { _ in refresh() }
                HStack {
                    Text("−24h").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(relativeLabel()).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("bây giờ").font(.caption).foregroundStyle(.secondary)
                }
            }

            // D. Bottom line describes the SELECTED moment (moves with the
            // slider), never the capture engine — no more mystery numbers.
            HStack {
                Circle()
                    .fill(cap.paused ? .orange : (cap.permissionGranted ? .green : .red))
                    .frame(width: 8, height: 8)
                Text(viewedLine()).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("\(shots.count) ảnh / 24h").font(.caption).foregroundStyle(.secondary)
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
                Button {
                    NSWorkspace.shared.open(ShotStore.dir)
                } label: {
                    Label("Mở thư mục ảnh", systemImage: "folder")
                }
                .help("Mở thư mục chứa ảnh chụp")
            }
        }
        // Disk is scanned only at meaningful moments (window opens / regains
        // focus). In between, the view works purely from the cached list.
        .onAppear { reload(); cap.start() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            reload(keepPosition: true)
        }
    }

    // MARK: - Helpers

    private func selectedDate() -> Date { Date().addingTimeInterval(-span + fraction * span) }

    /// Currently viewed shot (follows the slider), for the bottom line.
    private func viewedShot() -> ShotStore.Shot? {
        ShotStore.nearest(to: selectedDate(), in: shots)
    }

    private func refresh() {
        let t = selectedDate()
        if let s = viewedShot() {
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

    private func reload(keepPosition: Bool = false) {
        shots = ShotStore.list().filter { $0.date > Date().addingTimeInterval(-span) }
        if shots.isEmpty {
            image = nil
            caption = "Chưa có ảnh nào — app sẽ chụp mỗi phút khi bạn dùng máy."
            isEmpty = true
        } else {
            if !keepPosition { fraction = 1.0 }
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

    /// Bottom line: always about the moment being viewed (follows slider).
    private func viewedLine() -> String {
        let t = selectedDate()
        if isEmpty {
            return "Máy nghỉ lúc \(timeString(for: t)) — không có ảnh"
        }
        var parts = ["Đang xem ảnh lúc \(caption)"]
        if let s = viewedShot() {
            var ctx: [String] = []
            if let a = s.app { ctx.append(a) }
            if let d = s.detail { ctx.append(d) }
            if !ctx.isEmpty { parts.append(ctx.joined(separator: " • ")) }
        }
        parts.append(relativeLabel())
        return parts.joined(separator: " • ")
    }

    private func relativeLabel() -> String {
        let mins = Int(round((1.0 - fraction) * span / 60))
        if mins < 1 { return "hiện tại" }
        if mins < 60 { return "\(mins) phút trước" }
        return "\(mins / 60)h\(mins % 60 == 0 ? "" : "\(mins % 60)p") trước"
    }

}
