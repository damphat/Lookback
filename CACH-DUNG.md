# Lookback — chạy app

```bash
./build.sh        # build ra dist/Lookback.app
open dist/Lookback.app
```

Lần đầu: System Settings > Privacy & Security > Screen Recording > bật Lookback,
rồi mở lại app. Icon đồng hồ xuất hiện trên Menu Bar — bấm vào để xem lại 24h qua.

- Ảnh lưu ở `~/.lookback/`, tự xóa sau 7 ngày.
- Tiết kiệm pin: chỉ chụp mỗi 60s khi bạn đang dùng máy (nghỉ 10 phút thì thôi),
  màn hình đứng yên thì không lưu trùng, ảnh thu nhỏ còn 1280px.
