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
  nếu bị chìm; chuột phải = menu (mở cửa sổ, tạm dừng/tiếp tục, giới thiệu,
  thoát). Hiện menu bằng `NSMenu.popUp(positioning:at:in:)`
  (`NSStatusItem.popUpMenu` đã deprecated).
- Cửa sổ tạo tay bằng `NSWindow` + `NSHostingController`, style chuẩn
  (titled/closable/miniaturizable/resizable) để resize và fullscreen được.
  Đóng cửa sổ (`windowWillClose`) thì hủy window controller để dọn timer,
  thumbnail; mở lại thì state mới.
- **About**: `orderFrontStandardAboutPanel`, lấy tên/icon/version từ Info.plist.

## 3. Pipeline chụp (tiết kiệm pin là ưu tiên số 1)

- Chu kỳ 60s trên queue `.utility`, dùng `CGDisplayCreateImage` màn hình chính.
- Bỏ qua khi máy nghỉ: `CGEventSource.secondsSinceLastEventType(.hidSystemState,
  eventType: any-input)` > 10 phút thì không chụp.
  (Cẩn thận: sai event source/type sẽ khiến app không bao giờ chụp.)
- Bỏ qua ảnh trùng pixel (hash MD5 so với lần trước).
- Downscale còn tối đa 1280px, nén JPEG quality ~0.45.
- Lưu `~/.lookback/YYYY-MM-DD_HH-mm-ss.jpg`, tự xóa file quá 7 ngày.
- Không bao giờ gọi `CGRequestScreenCaptureAccess()` tự động (macOS sẽ spam
  dialog mỗi lần mở). Chỉ gọi khi user bấm nút "Cấp quyền".
- Nếu khởi động mà chưa có quyền: **tự bung cửa sổ** để user thấy banner cảnh
  báo, tránh chạy cả ngày mà không có ảnh nào.

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
- Sidebar preset khung giờ dùng chung 2 tab (`TimeScope`). Tab Thống kê cộng
  phút từ `summary()` nên khớp tuyệt đối với bar.
- Danh sách file chỉ quét đĩa khi mở cửa sổ và khi cửa sổ được focus lại;
  lúc kéo chỉ đọc cache RAM. Không timer poll, không nút "Làm mới".
- Trạng thái trống: "Máy nghỉ lúc HH:mm" / "Chưa có hoạt động nào".

## 5. Đóng gói & kiểm thử

- SwiftPM (`swift build -c release`), script build ra `.app` gồm binary +
  Info.plist + `.icns` (vẽ icon bằng code rồi `iconutil -c icns` cũng được).
- Unit test khóa bất biến kiến trúc: regions lát khít không chồng/khe,
  `view(at:)` trong vùng app luôn có shot, stats = tổng region, tick không
  chồng chữ, màu các app phổ biến đôi một khác nhau (`swift test`).
- Kiểm thử tay: mở app khi có/không có quyền, click trái/phải tray, kéo
  slider nhiều vị trí (kể cả vùng ngủ), đổi preset, đóng/mở lại cửa sổ,
  rebuild rồi cấp quyền lại.

## 6. Non-goals

Không đồng bộ cloud, không nhận diện nội dung/OCR, không quay video, không
giữ ảnh quá 7 ngày, không thêm nút/tùy chọn ngoài danh sách trên.
