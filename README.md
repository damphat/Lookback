# Lookback

Ứng dụng macOS giúp bạn trả lời câu hỏi "cả ngày nay mình đã làm gì?" —
tự động chụp màn hình mỗi phút khi bạn đang dùng máy, và cho xem lại 24 giờ
qua trên một timeline trực quan.

![Icon](Resources/Lookback.icns)

## Tính năng

- **Chụp nền tiết kiệm pin:** mỗi 60 giây chụp màn hình chính một lần, chỉ khi
  bạn đang dùng máy (nghỉ tay quá 10 phút thì thôi), màn hình đứng yên thì
  không lưu trùng, ảnh thu nhỏ còn 1280px + nén JPEG.
- **Chạy ngầm:** không icon Dock, chỉ một icon đồng hồ trên Menu Bar.
  Chuột trái vào icon = mở / lôi cửa sổ lên, chuột phải = menu
  (mở cửa sổ, tạm dừng, giới thiệu, thoát).
- **Timeline 24h:** ảnh lớn + dải 48 ô thumbnail (mỗi ô 30 phút, ô nào máy nghỉ
  thì xám) + slider. Bấm ô nào nhảy tới giờ đó.
- **Overlay thông minh:** đang kéo slider thì hiện giờ to giữa ảnh (giờ lớn,
  ngày nhỏ, "X phút trước"); thả ra thì thu thành pill nhỏ góc ảnh.
- **Tự bảo vệ user:** chưa cấp quyền Screen Recording thì app tự bung cửa sổ
  báo ngay, không bao giờ hỏi xin quyền một cách tự động và spam.
- **Lưu trữ gọn:** ảnh JPG ở `~/.lookback/`, tên theo
  `YYYY-MM-DD_HH-mm-ss.jpg`, tự xóa file quá 7 ngày.
- Đóng cửa sổ là dọn sạch viewer (timer, thumbnail); chụp nền vẫn chạy.

## Cài đặt & chạy

```bash
./build.sh              # build ra dist/Lookback.app
open dist/Lookback.app
```

Lần đầu (và sau mỗi lần build lại — macOS coi binary mới là app mới):
System Settings → Privacy & Security → Screen Recording → tick **Lookback**,
rồi mở lại app.

## Yêu cầu

- macOS 13+, Xcode 16+ (để build), Swift 5.9+
- Quyền Screen Recording (bắt buộc để chụp màn hình)

## Cấu trúc mã nguồn

```
Package.swift                  # SwiftPM, target Lookback + LookbackTests
Sources/Lookback/
  LookbackApp.swift            # @main, Settings scene (không cửa sổ lúc mở app)
  AppDelegate.swift            # tray icon, menu chuột phải, tạo/hủy cửa sổ, About
  CaptureService.swift         # vòng lặp chụp nền (singleton, sống cùng app)
  ShotStore.swift               # đọc/ghi/tìm ảnh trong ~/.lookback
  ThumbCache.swift              # cache thumbnail cho dải activity
  TimelineView.swift            # giao diện xem lại 24h
Resources/
  Info.plist                   # LSUIElement, icon, mô tả quyền
  Lookback.icns                # icon app
Tests/LookbackTests/
  ShotStoreTests.swift          # 4 test logic chọn ảnh theo slider
```

Quy ước: xem [CHANGELOG.md](CHANGELOG.md) khi đổi hành vi, và
[RECREATE.md](RECREATE.md) là bản spec đầy đủ để tái tạo app này.
