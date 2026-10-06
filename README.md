# Lookback

Ứng dụng macOS giúp bạn trả lời câu hỏi "cả ngày nay mình đã làm gì?" —
tự động chụp màn hình mỗi phút khi bạn đang dùng máy, và cho xem lại trên
một timeline trực quan theo miền thời gian (mọi con số là phút, không đếm
ảnh).

![Icon](Resources/Lookback.icns)

## Tính năng

- **Chụp nền tiết kiệm pin:** mỗi 60 giây chụp màn hình chính một lần, chỉ khi
  bạn đang dùng máy (nghỉ tay quá 10 phút thì thôi), màn hình đứng yên thì
  không lưu trùng, ảnh thu nhỏ còn 1280px + nén JPEG.
- **Chạy ngầm:** không icon Dock, chỉ một icon đồng hồ trên Menu Bar.
  Chuột trái vào icon = mở / lôi cửa sổ lên, chuột phải = menu duy nhất
  **Tạm dừng/Tiếp tục chụp** + Thoát. Đang dừng thì icon mờ đi + tooltip báo
  rõ (icon = trạng thái, menu = hành động — không dùng glyph ⏸ mơ hồ).
- **Timeline theo miền thời gian:** ảnh lớn + dải readout giờ-đang-chọn +
  thanh activity 2 cấp (vùng app/vùng ngủ, bên trong là từng website/folder
  project với màu cùng họ). Thanh activity chính là slider: bấm/kéo điểm nào
  cũng chạy. Trục giờ `TimeRuler` tự giãn tick, đầu phải là "now".
- **Sidebar khung giờ:** 1h / 6h / 24h / Hôm nay / Sáng hôm qua — dùng chung
  cho cả Timeline và Thống kê, lựa chọn được nhớ qua lần mở sau.
- **Window sống:** ảnh mới tự đẩy vào cửa sổ đang mở (không nút refresh);
  mép phải trôi theo "now"; con trỏ đang ở "now" thì bám mép khi có ảnh mới
  hay đổi khung (luật live-pin duy nhất trong `rescope()`).
- **Hoverpopup nhất quán:** một layout cho mọi vùng (tên + một duration nổi
  bật + khoảng giờ + tối đa 5 vùng con + preview ảnh).
- **Thống kê theo phút:** tab riêng cộng thời gian từ đúng regions mà thanh
  bar đang vẽ nên số liệu khớp tuyệt đối, bung ra xem từng website/folder.
- **Tự bảo vệ user:** thiếu quyền Screen Recording hay Automation thì app tự
  bung cửa sổ báo ngay từ lúc khởi động, không bao giờ hỏi xin quyền một
  cách tự động và spam. Banner Automation chỉ một nút (thử dialog consent,
  im lặng thì mở thẳng Settings) và dính cho tới khi được cấp — không chớp
  tắt theo chu kỳ chụp.
- **Lưu trữ gọn:** ảnh JPG ở `~/.lookback/`, tên theo
  `YYYY-MM-DD_HH-mm-ss[__app[__detail]].jpg` (Chrome → domain, VSCode →
  tên folder), tự xóa file quá 7 ngày.
- Đóng cửa sổ là dọn sạch viewer (timer, thumbnail); chụp nền vẫn chạy.

## Cài đặt & chạy

```bash
./install.sh            # build + cài vào /Applications + mở lại app
```

`install.sh` tự tắt bản đang chạy, xóa sạch bản cũ rồi chép bằng `ditto`
(không dùng `cp -R`: nó chồng lên `.app` cũ để lại file thừa, chép đè app
đang chạy, và dễ gãy chữ ký). Muốn chỉ build không cài:

```bash
./build.sh              # build ra dist/Lookback.app
open dist/Lookback.app
```

Lần đầu (và sau mỗi lần build lại ký ad-hoc — macOS coi binary mới là app
mới): System Settings → Privacy & Security → Screen Recording → tick
**Lookback**, rồi mở lại app. Test lại quy trình cấp quyền từ đầu bằng
`./reset-permissions.sh` (reset đúng bundle id `com.lookback.app`).

## Yêu cầu

- macOS 13+, Xcode 16+ (để build), Swift 5.9+
- Quyền Screen Recording (bắt buộc để chụp màn hình)
- Quyền Automation → Chrome (optional, để ghi tên website; thiếu thì banner
  báo và tên file về timestamp-only)

## Cấu trúc mã nguồn

```
Package.swift                  # SwiftPM, target Lookback + LookbackTests
build.sh / install.sh          # build ra dist/ / build + cài vào /Applications
reset-permissions.sh           # reset 2 quyền để test cấp quyền từ đầu
Sources/Lookback/
  LookbackApp.swift            # @main, Settings scene (không cửa sổ lúc mở app)
  AppDelegate.swift            # tray icon/state (TrayState), menu start-stop,
                               tạo/hủy cửa sổ, QuitGate
  CaptureService.swift         # vòng lặp chụp nền (singleton) + generation
                               (đẩy ảnh mới) + 2 cổng quyền + fixAutomation()
  ShotStore.swift              # đọc/ghi/tìm ảnh trong ~/.lookback
  ThumbCache.swift             # cache thumbnail cho popup hover
  ActivityState.swift          # single source of truth: cell-model thời gian,
                               regions 2 cấp, view(at:), summary()
  AppActivityBar.swift         # thanh activity = slider duy nhất + popup hover
  TimeRuler.swift              # trục giờ tái dùng (model thuần + view)
  TimeScope.swift              # preset (persist) + tick (chỗ duy nhất ghi
                               window) + luật live-pin isLive()
  TimeText.swift               # mọi chuỗi thời gian: short/long/ago
  AppPalette.swift             # màu app cố định + shade vùng con theo thứ tự
  TimelineView.swift           # ảnh + readout giờ-đang-chọn + bar + sidebar,
                               rescope() là lối vào duy nhất mọi đổi window
  StatsView.swift              # thống kê phút từ summary()
Resources/
  Info.plist                   # LSUIElement, icon, mô tả quyền, version
  Lookback.icns                # icon app
Tests/LookbackTests/
  ActivityStateTests.swift     # bất biến lát phủ, view() single-truth, summary
  TimeRulerTests.swift         # tick thích ứng, màu đôi một khác nhau, TimeText
  ShotStoreTests.swift         # filename 3 phần, nearest, summary theo window
  TimelineLayoutTests.swift    # biên hình học viewer
  ScopePinTests.swift          # live-pin, tick trôi/đứng, persist preset
  TrayStateTests.swift         # mapping tray state→UI không đảo ngược
  AutomationStatusTests.swift  # mapping trạng thái consent Automation
  QuitGateTests.swift          # chặn Cmd+Q, chỉ tray-Thoát/system được thoát
```

Kiến trúc: `ActivityState` sở hữu toàn bộ logic thời gian (mỗi sample một
cell, region = hợp cell, sleep = phần bù); view chỉ vẽ `regions()` và hỏi
`view(at:)` — không dung sai riêng ở bất kỳ caller nào. Window = f(preset,
now): `TimeScope.tick()` là chỗ duy nhất ghi `from`/`to`, còn selection là
ghim ở mép phải (trong 90s của `to` nghĩa là "đang xem now") nên mọi đổi
window dồn qua một `rescope()`. Tray: icon giữ một mặt thể hiện state (mờ khi
dừng), menu giữ động từ thể hiện action; sink của `$paused` phải xài giá trị
emitted (vì `@Published` bắn từ `willSet`, đọc lại property là thấy state cũ).

Quy ước: xem [CHANGELOG.md](CHANGELOG.md) khi đổi hành vi, và
[RECREATE.md](RECREATE.md) là bản spec đầy đủ để tái tạo app này.
