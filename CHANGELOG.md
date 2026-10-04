# Changelog

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
