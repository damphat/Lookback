# Tái tạo Lookback (prompt cho AI)

> Dán toàn bộ nội dung dưới đây cho AI để làm ra app tương tự hoặc tốt hơn.
> Ngôn ngữ UI: tiếng Việt. Platform: macOS 13+, Swift + SwiftUI + AppKit.

## 1. Bài toán

Người dùng hay quên mình đã làm gì trên máy tính. Hãy làm app macOS tên
"Lookback": âm thầm chụp màn hình theo chu kỳ, cho xem lại 24 giờ qua trên
timeline trực quan. Đơn giản, hiện đại, tiết kiệm pin.

## 2. Kiến trúc bắt buộc

- **Agent-app** (`LSUIElement = true`): không icon Dock, không cửa sổ lúc khởi
  động. Sống qua `NSApplicationDelegate`, không qua `Window` scene
  (Window scene sẽ tự bung cửa sổ lúc mở app — sai yêu cầu).
- **Singleton capture** sống cùng app, độc lập với cửa sổ: đóng cửa sổ không
  được dừng chụp.
- **Tray icon** (`NSStatusItem`, code tay, không dùng `MenuBarExtra` vì cần
  phân biệt chuột): chuột trái = mở cửa sổ nếu chưa có, `activate` + lôi lên
  nếu bị chìm; chuột phải = menu chỉ gồm start/stop duy nhất (Tạm dừng/Tiếp
  tục chụp) + Thoát. Hiện menu bằng `NSMenu.popUp(positioning:at:in:)`
  (`NSStatusItem.popUpMenu` đã deprecated).
- **Luật tray (cấm mơ hồ state/action):** icon giữ đúng một mặt mọi lúc, thể
  hiện state bằng mờ (`appearsDisabled` khi dừng) + tooltip; menu giữ động từ
  thể hiện action. Cấm glyph ⏸ trên icon. Gom mapping vào type thuần test
  được. Bẫy Combine: `@Published` bắn từ `willSet`, nên sink của `$paused`
  bắt buộc xài giá trị emitted — đọc lại property là thấy state CŨ (tray lag
  đúng 1 nhịp rồi đảo ngược).
- Cửa sổ tạo tay bằng `NSWindow` + `NSHostingController`, style chuẩn
  (titled/closable/miniaturizable/resizable) để resize và fullscreen được.
  Đóng cửa sổ (`windowWillClose`) thì hủy window controller để dọn timer,
  thumbnail; mở lại thì state mới (nhưng preset khung giờ được nhớ qua
  UserDefaults).

## 3. Pipeline chụp (tiết kiệm pin là ưu tiên số 1)

- Chu kỳ 60s trên queue `.utility`, dùng `CGDisplayCreateImage` màn hình chính.
- Bỏ qua khi máy nghỉ: `CGEventSource.secondsSinceLastEventType(.hidSystemState,
  eventType: any-input)` > 10 phút thì không chụp.
  (Cẩn thận: sai event source/type sẽ khiến app không bao giờ chụp.)
- Bỏ qua ảnh trùng pixel (hash MD5 so với lần trước).
- Downscale còn tối đa 1280px, nén JPEG quality ~0.45.
- Lưu `~/.lookback/YYYY-MM-DD_HH-mm-ss[__app[__detail]].jpg` (Chrome →
  domain tab đang mở, VSCode → tên folder project; thiếu context thì về tên
  timestamp-only như cũ), tự xóa file quá 7 ngày. Mỗi shot lưu xong bump một
  counter `generation` trên main thread để window đang mở tự cập nhật.
- Không bao giờ gọi `CGRequestScreenCaptureAccess()` tự động (macOS sẽ spam
  dialog mỗi lần mở). Chỉ gọi khi user bấm nút "Cấp quyền".
- **Hai cổng quyền check ngay khi khởi động** (Recording + Automation): thiếu
  cổng nào **tự bung cửa sổ** để user thấy banner, tránh chạy mù cả ngày.
- Automation (đọc URL Chrome qua AppleScript): vòng lặp nền KHÔNG BAO GIỜ
  được xin consent (`askUserIfNeeded: false`) — fresh install không thể lọt
  vào danh sách Automation nếu chưa có cú bấm chủ động của user. Chỉ một nút
  duy nhất: thử dialog consent trước, macOS im lặng (đã từng deny) thì mở
  thẳng Settings Privacy_Automation. Denial là latch dính: chỉ moment Chrome
  đang frontmost mới được chạm latch (set khi deny, clear khi granted) — cấm
  clear vì "Chrome không frontmost", nếu không banner chớp tắt theo chu kỳ.

## 4. Viewer (miền thời gian, không đếm ảnh)

- Trục dọc: ảnh lớn co giãn → dải readout giờ-đang-chọn (giờ to + ngữ cảnh,
  canh giữa) → `AppActivityBar` → `TimeRuler`. Không pill góc ảnh, không dòng
  status bottom, không slider riêng: **bar chính là slider** (bấm/kéo mọi
  điểm đều chạy, kể cả vùng ngủ).
- Mọi số liệu là phút (`TimeText`: short/long/ago), không chỗ nào đếm ảnh.
- `ActivityState` là single source of truth: mỗi sample một cell thời gian
  (chia đôi với ảnh kề, tối đa ±sleepGap/2), region = hợp cell, sleep = phần
  bù; regions lát khít khung nhìn. Mọi hiển thị (màu, popup, viewer, thống
  kê) đều từ `regions()` + `view(at:)` — cấm dung sai/tolerance riêng ở
  caller. Màu qua `AppPalette` (app cố định, vùng con = shade theo thứ tự).
- Sidebar preset khung giờ dùng chung 2 tab (`TimeScope`), persist qua
  UserDefaults nên mở lại vẫn giữ. Tab Thống kê cộng phút từ `summary()` nên
  khớp tuyệt đối với bar.
- **Mental model window:** Window = f(preset, now). `tick()` là chỗ DUY NHẤT
  ghi `from`/`to` (preset trôi bám "now" mỗi tick, preset cố định chỉ tính khi
  force). Selection là ghim ở mép phải: trong ~90s của `to` nghĩa là "đang xem
  now". MỌI đổi window (mở app, đổi preset, shot mới qua `generation`, tick
  30s, focus lại window, bấm banner quyền) dồn qua đúng một `rescope()`:
  đang live thì bám mép mới, không thì clamp — cấm `keepPosition`/clamp rời
  rạc từng call site. Không nút "Làm mới".
- Trạng thái trống: "Máy nghỉ lúc HH:mm" / "Chưa có hoạt động nào".

## 5. Đóng gói & kiểm thử

- SwiftPM (`swift build -c release`), script build ra `.app` gồm binary +
  Info.plist + `.icns` (vẽ icon bằng code rồi `iconutil -c icns` cũng được).
  Cài vào `/Applications`: tắt app đang chạy → `rm -rf` bản cũ → chép bằng
  `ditto` (cấm `cp -R`: chồng lấp để lại file thừa, chép đè app đang chạy,
  gãy chữ ký).
- Unit test khóa bất biến kiến trúc (`swift test`): regions lát khít không
  chồng/khe, `view(at:)` trong vùng app luôn có shot, stats = tổng region,
  tick không chồng chữ, màu các app phổ biến đôi một khác nhau, live-pin +
  persist preset, mapping tray state→UI không đảo ngược, mapping consent
  Automation, QuitGate chặn Cmd+Q.
- Kiểm thử tay: mở app khi có/không có từng quyền, click trái/phải tray,
  toggle dừng/tiếp tục (icon mờ + tooltip khớp, không lag/đảo), kéo slider
  nhiều vị trí (kể cả vùng ngủ), đổi preset (nhớ qua lần mở sau), để con trỏ
  ở now rồi chờ shot mới (phải bám mép), đóng/mở lại cửa sổ, rebuild rồi cấp
  quyền lại.

## 6. Non-goals

Không đồng bộ cloud, không nhận diện nội dung/OCR, không quay video, không
giữ ảnh quá 7 ngày, không thêm nút/tùy chọn ngoài danh sách trên.
