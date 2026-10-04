# Bối cảnh & Mục tiêu
Viết một ứng dụng macOS tên là "Lookback" chạy dưới dạng Menu Bar (trên thanh trạng thái) bằng Swift/SwiftUI. Ứng dụng tự động chụp màn hình mỗi phút, nén chuẩn JPG để tiết kiệm dung lượng đĩa, và cung cấp một cửa sổ giao diện (Window) xem lại lịch sử làm việc trong 24 giờ qua thông qua thanh trượt (slider) và thanh chỉ báo hoạt động (Activity Bar).

---

# Yêu cầu Kỹ thuật & Tính năng Chính

## 1. Tự động Chụp & Nén Màn hình (Background Scheduler)
- **Tần suất**: Chụp đúng mỗi 1 phút một lần.
- **Thư mục lưu trữ**: `~/.screenshots/` (tự động tạo thư mục nếu chưa có).
- **Định dạng file**: Cố định là **JPG** (Sử dụng chất lượng nén `JPEG compression quality = 0.3 - 0.4` để dung lượng tối ưu nhẹ nhất).
- **Quy tắc đặt tên file**: Dạng timestamp chuẩn: `YYYY-MM-DD_HH-mm-ss.jpg`.
- **Tự động dọn dẹp**: Tự động xóa các file JPG cũ hơn 24 giờ để tiết kiệm ổ cứng.

## 2. Tích hợp Menu Bar & Cửa sổ Giao diện (Window UI)
- Lookback chạy dưới dạng `NSStatusItem` trên thanh menu macOS.
- **Mặc định**: Chạy ẩn hoàn toàn dưới nền, không hiện icon dưới thanh Dock (`LSUIElement = true` trong `Info.plist`).
- **Tương tác**: Khi bấm vào Icon Lookback trên Menu Bar -> **Mở trực tiếp một Cửa sổ UI chuẩn (Standard NSWindow / SwiftUI Window)** thay vì dạng Popover thả xuống.
- Khi đóng cửa sổ, ứng dụng vẫn tiếp tục chạy ẩn trên Menu Bar.

## 3. Giao diện Người dùng (GUI Viewer)
Bố cục theo chiều dọc (`VStack`) gồm 3 phần chính từ trên xuống dưới:

### A. Màn hình Xem Ảnh (`Expanded Image View`)
- Hiển thị ảnh chụp màn hình tương ứng với mốc thời gian đang chọn trên Slider.
- **Overlay Thông tin**: Đè thông tin ngày giờ (`YYYY-MM-DD HH:mm:ss`) lên góc ảnh.
- **Trạng thái Trống (Empty State / Sleep Zone)**: Nếu thời điểm được chọn không tìm thấy ảnh trong vòng ±1 phút (do máy đang sleep/tắt máy hoặc app không chạy), hiển thị một màn hình chờ Placeholder màu xám mờ với thông báo "Máy nghỉ / Không có ảnh chụp tại thời điểm HH:mm".

### B. Thanh Chỉ báo Hoạt động (`Activity Bar / Timeline Matrix`) - Nằm ở giữa
- Nằm giữa Màn hình xem ảnh và Slider.
- **Cấu trúc**: Chia thành 24 hoặc 48 ô chữ nhật nhỏ tương ứng với 24 giờ qua (mỗi ô là 1h hoặc 30 phút).
- **Trạng thái trực quan**:
  - Ô sáng / có màu: Thời gian đó có dữ liệu ảnh chụp (máy đang hoạt động).
  - Ô màu tối / xám mờ: Khoảng thời gian máy sleep hoặc không có ảnh chụp.
- **Tương tác**: Click vào bất kỳ ô nào trên Activity Bar sẽ nhảy Slider và ảnh tới ngay mốc thời gian đó.

### C. Thanh Trượt Thời gian (`Slider View`) & Logic Chọn Ảnh
- **Mốc Slider**: Từ `0.0` (24 giờ trước: `Date() - 24h`) đến `1.0` (Hiện tại: `Date()`).
- **Logic Xác định Ảnh**:
  1. Khi kéo Slider, tính toán `selectedDate`.
  2. Tìm kiếm trong danh sách file ảnh ở `~/.screenshots/` file có mốc thời gian gần nhất với `selectedDate`.
  3. Nếu chênh lệch thời gian giữa `selectedDate` và file tìm được <= 60 giây -> Tải và hiển thị ảnh đó.
  4. Nếu chênh lệch > 60 giây -> Chuyển Image View sang trạng thái "Empty State / Sleep Zone".

---

# Hướng dẫn Kiến trúc & Triển khai

- **Ngôn ngữ & Framework**: Swift, SwiftUI, AppKit (`NSStatusItem`, `NSWindowController`).
- **Chụp màn hình**: Sử dụng `ScreenCaptureKit` (macOS 12.3+) hoặc `CGWindowListCreateImage`.
- **Cấp quyền (Permissions)**:
  - Kiểm tra và xin quyền **Screen Recording** (`CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()`).
- **Tối ưu Hiệu năng**:
  - Chụp, nén JPG và lưu file chạy hoàn toàn dưới luồng nền (`DispatchQueue.global(qos: .utility)`).
  - Tải ảnh khi kéo Slider cần sử dụng bộ nhớ đệm (Cache) đơn giản để thao tác mượt mà, không bị khựng/trễ giao diện.

---

# Sản phẩm Đầu ra (Deliverables)
1. Mã nguồn Xcode project / các file Swift hoàn chỉnh cho ứng dụng **Lookback**.
2. File `Info.plist` đã cấu hình `LSUIElement = YES` và mô tả quyền Screen Recording.
3. Hướng dẫn chi tiết cách Build, Chạy và Cấp quyền Screen Recording trên macOS.