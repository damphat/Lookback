#!/bin/bash
# Reset 2 quyền của Lookback để test lại quá trình cấp quyền từ đầu:
#   - ScreenCapture (chụp màn hình)
#   - AppleEvents  (Automation: đọc tab Chrome)
# Chỉ reset đúng bundle id com.lookback.app, không đụng app khác.
set -e
APP_ID="com.lookback.app"
echo "Thoát Lookback trước (Cmd+Q bị chặn — chuột phải tray icon → Thoát), rồi Enter."
read -r _
if pgrep -x Lookback >/dev/null; then
    echo "Lookback vẫn đang chạy, đang tắt…"
    pkill -x Lookback
    sleep 1
fi
tccutil reset ScreenCapture "$APP_ID"
tccutil reset AppleEvents "$APP_ID"
echo "Xong. Mở app lại để macOS hỏi quyền từ đầu."
