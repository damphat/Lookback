- [x] ghi nhớ setting, không nên cứ mở window là nó quay về khung thời gian 24h
      → TimeScope.preset persist qua UserDefaults (key lookback.timePreset).
- [x] tự động cập push ảnh vào window nếu window đang mở (không cần phải refresh)
      → CaptureService.generation +1 mỗi shot mới; Timeline/Stats tự rescope/reload. Tick 30s trôi mép window kể cả khi idle.
- [x] nếu con trỏ đang ở vị trí now, mà thêm ảnh hoặc khung thay đổi thì nó vẫn là now (cần mental model cho cái này giúp đơn giản hóa code, không nên sửa manh mún khiến code dài ra)
      → Mental model "live-pin": selection trong 90s của mép phải nghĩa là "đang xem now".
      Mọi thay đổi window đi qua đúng 1 hàm TimelineView.rescope() (xóa reload(keepPosition:)/clampSelection rời rạc);
      TimeScope.tick() là chỗ duy nhất ghi from/to. Test: ScopePinTests.
- [x] Hiện giờ khi mất quyền automation một UI hiện hiện ra với 2 button, button thứ nhất có vẻ không hoạt động? Cái thứ 2 thì ổn vì nó mở UI hệ thống.
      → Gộp thành 1 nút duy nhất CaptureService.fixAutomation(): thử dialog consent trước,
      nếu macOS im lặng (đã từng deny) thì mở thẳng Settings — nút bấm luôn thấy được kết quả.
      Nguyên nhân nút cũ "chết": sau lần deny đầu, AEDeterminePermissionToAutomateTarget(ask:true) không hiện gì nữa.
- [x] Có thể cấp quyền automation ngay khi mở app như recording được không nhỉ? ... Cái thanh báo lỗi đó cứ hiện rồi tắt trong chu kỳ 1 phút.
      → CaptureService.start() check cả 2 cổng (recording + automation); thiếu cổng nào AppDelegate bung window ngay.
      ActiveContext.chromeDenied thành latch dính (sticky): chỉ moment Chrome-frontmost mới được chạm latch,
      hết hiện-tắt theo chu kỳ capture.
- [x] Trạng thái dừng chụp thì phải thể hiện gì đó trên tray icon. Chỉ nên có duy nhất start/stop trên context menu của tray icon, bỏ cái checkbox trong window
      → Menu tray chỉ còn [Tạm dừng/Tiếp tục chụp, Thoát]; icon đổi pause.circle.fill + tooltip khi dừng;
      checkbox trong window xóa, chỉ còn dòng trạng thái read-only.
- [x] (follow-up) Tray lag 1 nhịp rồi đảo ngược: sink bỏ qua giá trị emitted mà đọc lại cap.paused,
      nhưng @Published bắn từ willSet nên luôn thấy state CŨ. Sửa: truyền giá trị emitted xuống refreshTrayIcon(paused:).
      Đồng thời bỏ icon ⏸ (mơ hồ state/action): icon giữ một mặt, dừng = dimmed + tooltip; menu giữ động từ
      (state ở icon, action ở menu). Mapping thuần gom vào TrayState, khóa bằng TrayStateTests.
