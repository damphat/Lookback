# Changelog

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
