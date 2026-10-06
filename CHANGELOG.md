# Changelog

## 1.5 — 2026-10-06

Lô TODO menu/window + fix đảo ngược trạng thái tray. Mental model gọn: window
= f(preset, now), selection là ghim ở mép phải.

- Nhớ khung giờ đã chọn (persist preset, mở window không về 24h nữa).
- Ảnh mới tự đẩy vào window đang mở (không cần refresh tay); mép window trôi
  theo "now" mỗi 30s kể cả khi máy idle.
- Con trỏ ở "now" thì bám mép khi có ảnh mới/đổi khung; mọi thay đổi window đi
  qua đúng một hàm `rescope()` (xóa `reload(keepPosition:)`/`clampSelection`).
- Banner Automation gộp 2 nút thành 1 (`fixAutomation()`: thử dialog consent,
  im lặng thì mở thẳng Settings). Check cả 2 cổng quyền ngay khi khởi động;
  denial thành latch dính, hết chớp tắt theo chu kỳ capture.
- Tray menu chỉ còn start/stop + Thoát; bỏ checkbox trong window. Fix tray lag
  1 nhịp rồi đảo ngược (sink đọc lại `paused` trong khi `@Published` bắn từ
  `willSet`): icon giữ một mặt, dừng = mờ + tooltip; mapping thuần `TrayState`
  có test khóa.

## Chưa phát hành

- `NSAppleEventsUsageDescription` trong Info.plist (thiếu key này macOS deny
  Automation im lặng, không hiện dialog).
- Phát hiện deny Automation (`AEDeterminePermissionToAutomateTarget`, không
  tự pop dialog) + banner cam hướng dẫn mở Settings Automation và nút kiểm
  tra lại, tương tự banner Screen Recording.
- Chặn Cmd+Q vô tình (`QuitGate`: chỉ thoát từ tray menu Thoát; logout/
  restart/shutdown vẫn qua).

## 1.2 — 2026-10-05

Refactor lớn sang miền thời gian (chuẩn bị cho tương lai bỏ ảnh): UI không
đếm ảnh nữa, mọi con số là phút, mọi độ rộng là thời gian.

- `ActivityState` cell-model: mỗi sample sở hữu một cell thời gian (chia đôi
  với ảnh kề, tối đa ±150s); region = hợp các cell nên số phút và số ảnh khớp
  nhau theo cấu trúc, không còn padding/clamp vá. Một lookup duy nhất
  `view(at:)` cho cả hover, viewer và thống kê.
- Thanh activity là slider duy nhất (click/drag mọi điểm đều chạy, kể cả vùng
  ngủ); ô con là shade cùng họ màu app theo thứ tự (hết trùng màu hash),
  inset 1px, thấp gọn; ô nào cũng overlay thời lượng.
- `TimeRuler` tách riêng (model + view, có test): tick thích ứng không chồng
  chữ, mép phải là "now" khi window live.
- Popup một layout cho mọi vùng (tên + MỘT duration headline + khoảng giờ +
  tối đa 5 vùng con); bỏ dòng "Ảnh lúc … bấm để xem".
- Dải readout giờ-đang-chọn to giữa ảnh và bar; bỏ pill góc ảnh và dòng
  status bottom (trùng lặp, khó hiểu).
- Tab Thống kê cộng phút từ regions (`summary()`), khớp tuyệt đối với bar;
  preset khung giờ (1h/6h/24h/Hôm nay/Sáng hôm qua) dùng chung cho cả hai tab
  qua `TimeScope`. Mọi chuỗi thời gian qua `TimeText` (short/long/ago).
- Màu app: `AppPalette` (8 app quen gán cứng + vòng 12 màu), test khóa 7 app
  phổ biến đôi một khác màu.

## 1.1 — 2026-10-06

- Tên file 3 phần `timestamp__app__detail.jpg` (app/detail optional, file cũ
  vẫn đọc được): Chrome ghi thêm domain tab đang mở, VSCode ghi thêm tên
  folder project. Lấy context thất bại thì về tên timestamp-only như cũ.
- Tab "Thống kê": app trong ngày sort theo số ảnh (≈ số phút dùng), bung ra
  xem chi tiết từng website/folder. Dòng bottom timeline cũng hiện app •
  detail của ảnh đang xem.
- `AppActivityBar` (file riêng, tái dùng với mọi khung from/to): dải màu
  liên tục theo app, hover sáng cả vùng + popup (khoảng giờ, thời lượng,
  preview ảnh tại chuột), click chọn ảnh. Thay thế dải 48 ô cũ.
- Bar: vùng sleep cũng hover được (popup "Máy nghỉ" + khoảng giờ + số
  phút); nhấn-giữ và drag để scrub toàn bar; viền hover vẽ cùng frame với
  ô; popup chuyển ra overlay nên không còn đẩy layout.

## 1.0 — 2026-10-05

Bản đầu tiên dùng được hàng ngày.

- Chụp màn hình nền mỗi 60s (bỏ qua khi máy nghỉ > 10 phút, bỏ qua ảnh trùng,
  downscale 1280px, JPEG ~0.45), lưu `~/.lookback`, giữ 7 ngày.
- Agent-app: không Dock, chạy ngầm, icon Menu Bar (trái = mở cửa sổ,
  phải = menu).
- Viewer 24h: ảnh + dải 48 thumbnail + slider; overlay giờ to khi kéo,
  pill gọn khi thả; dòng bottom mô tả đúng khoảnh khắc đang xem.
- Chưa có quyền thì tự bung cửa sổ báo; không bao giờ xin quyền tự động.
- App icon, About panel, fix `popUpMenu` deprecated → `NSMenu.popUp`.
- 4 unit test cho logic chọn ảnh (`swift test`).
