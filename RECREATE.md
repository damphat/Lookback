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

## 4. Viewer 24 giờ

- Ảnh lớn co giãn theo cửa sổ; dưới là `AppActivityBar` (file riêng):
  dải màu liên tục theo app (mỗi app một màu ổn định, khoảng trống = máy
  nghỉ), vạch giờ + nhãn from/mid/to tự theo khung quan sát, playhead trùng
  với slider; hover sáng cả vùng session và hiện popup (tên app, khoảng giờ,
  thời lượng, preview ảnh tại vị trí chuột); click chọn ảnh đó. Dưới nữa là
  slider full-width đồng bộ cùng `fraction`, nhãn thời gian nằm **dưới**
  slider. Bar nhận `from`/`to` tường minh nên tái dùng được cho mọi khung
  quan sát, không gắn cứng 24h.
- Overlay trên ảnh: **đang kéo slider** thì hiện khối to giữa ảnh (giờ 64pt,
  ngày nhỏ, "X phút trước"); **thả ra** thì thu thành pill nhỏ góc ảnh.
- Dòng cuối mô tả đúng khoảnh khắc đang xem và chạy theo slider
  (vd "Đang xem ảnh lúc 14:32 • 58 phút trước"), kèm số ảnh/24h. Tuyệt đối
  không hiện con số tĩnh của engine (vd "đã chụp lúc…") vì user tưởng bug.
- Danh sách file chỉ quét đĩa khi mở cửa sổ và khi cửa sổ được focus lại;
  lúc kéo slider chỉ đọc từ cache RAM. Không timer poll, không nút "Làm mới".
- Trạng thái trống: pill xám "Máy nghỉ / không có ảnh lúc HH:mm" khi điểm
  được chọn cách ảnh gần nhất quá ~90 giây.

## 5. Đóng gói & kiểm thử

- SwiftPM (`swift build -c release`), script build ra `.app` gồm binary +
  Info.plist + `.icns` (vẽ icon bằng code rồi `iconutil -c icns` cũng được).
- Unit test tối thiểu cho logic "tìm ảnh gần nhất trong tolerance, ngoài thì
  nil" — logic này mà sai thì slider hiển thị sai.
- Kiểm thử tay: mở app khi có/không có quyền, click trái/phải tray, kéo
  slider nhiều vị trí, đóng/mở lại cửa sổ, rebuild rồi cấp quyền lại.

## 6. Non-goals

Không đồng bộ cloud, không nhận diện nội dung/OCR, không quay video, không
giữ ảnh quá 7 ngày, không thêm nút/tùy chọn ngoài danh sách trên.
