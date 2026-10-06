#!/bin/bash
# Cài Lookback.app vào /Applications, một lệnh duy nhất:
#   ./install.sh
#
# Làm: build release -> tắt app đang chạy -> xóa bản cũ -> chép bằng ditto
# -> mở lại app mới.
#
# Vì sao KHÔNG dùng `cp -R` (những lỗi ông từng gặp):
#   1. cp -R CHỒNG lên .app cũ thay vì thay thế: file thừa của bản cũ
#      (binary, nib, resource đã xóa) còn sót lại, app chạy thành bản lai
#      nửa cũ nửa mới, lỗi khó hiểu.
#   2. cp -R vào app ĐANG CHẠY: binary đang mmap, chép đè gây crash hoặc
#      hệ thống từ chối, app treo ở trạng thái dở.
#   3. cp -R không giữ nguyên symlink/permission như ditto, dễ gãy code
#      signature khiến macOS chặn app không lý do rõ ràng.
# ditto là tool Apple khuyên dùng để cài .app (giữ symlink, permission,
# resource fork, chữ ký).
set -e
cd "$(dirname "$0")"

./build.sh

APP=Lookback
SRC="dist/$APP.app"
DEST="/Applications/$APP.app"

# Tắt bản đang chạy trước (LSUIElement app không có Dock nên quit bằng tên).
if pgrep -x "$APP" >/dev/null 2>&1; then
    echo "Đang tắt $APP cũ..."
    osascript -e "tell application \"$APP\" to quit" 2>/dev/null || true
    for _ in $(seq 1 20); do
        pgrep -x "$APP" >/dev/null 2>&1 || break
        sleep 0.5
    done
fi
if pgrep -x "$APP" >/dev/null 2>&1; then
    echo "$APP vẫn không thoát, kill."
    pkill -x "$APP"
    sleep 1
fi

# Xóa sạch bản cũ rồi mới chép (không chồng lấp như cp -R).
rm -rf "$DEST"
ditto "$SRC" "$DEST"
open "$DEST"
echo "OK: đã cài $DEST (bản $(defaults read "$DEST/Contents/Info" CFBundleShortVersionString))"
