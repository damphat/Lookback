#!/bin/bash
# Build Lookback.app into ./dist
#
# Chữ ký quyết định app có phải xin lại quyền sau mỗi build không:
# ad-hoc (mặc định khi không có gì) thì identity dính theo nội dung binary,
# build mới là mất quyền cũ. Ký bằng cert cá nhân (TeamID ổn định) thì
# mọi build sau giữ nguyên quyền.
#
# Script tự chọn như Xcode, không cần chỉ tay:
#   1. $LOOKBACK_CODESIGN_IDENTITY nếu ông export sẵn,
#   2. cert "Mac Developer"/"Apple Development" duy nhất trong keychain,
#   3. nhiều cert thì dùng ad-hoc và in danh sách để ông chọn,
#   4. không có cert nào thì ad-hoc.
# Cert lấy ở: Xcode → Settings → Accounts → Apple ID (free được) →
# Manage Certificates → dấu + → "Mac Development". Trả phí chỉ cần khi
# phát hành cho máy khác (Developer ID + notarize).
set -e
cd "$(dirname "$0")"

pick_identity() {
    if [ -n "${LOOKBACK_CODESIGN_IDENTITY:-}" ]; then
        echo "$LOOKBACK_CODESIGN_IDENTITY"
        return
    fi
    local names
    names=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -nE 's/^ *[0-9]+\) [A-F0-9]+ "(Mac Developer: [^"]+|Apple Development: [^"]+)".*$/\1/p')
    local count
    count=$(printf '%s' "$names" | grep -c .)
    if [ "$count" -eq 1 ]; then
        echo "$names"
    else
        echo "-"
    fi
}

swift build -c release
APP=dist/Lookback.app
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Lookback.icns "$APP/Contents/Resources/Lookback.icns"
cp .build/release/Lookback "$APP/Contents/MacOS/Lookback"
IDENTITY=$(pick_identity)
codesign --force --deep --sign "$IDENTITY" "$APP"
if [ "$IDENTITY" = "-" ]; then
    echo "OK: $APP (ký ad-hoc — macOS sẽ hỏi quyền lại sau build)"
    echo "Muốn hết hỏi: tạo cert Mac Development trong Xcode (Apple ID free được)."
    AVAIL=$(security find-identity -v -p codesigning 2>/dev/null | grep -E "\(Mac Developer|Apple Development): " || true)
    if [ -n "$AVAIL" ]; then
        echo "Thấy nhiều cert, chọn một rồi build lại với:"
        echo "$AVAIL"
        echo 'VD: LOOKBACK_CODESIGN_IDENTITY="Mac Developer: Tên Ông (TEAMID)" ./build.sh'
    fi
else
    echo "OK: $APP (ký: $IDENTITY — quyền giữ nguyên sau rebuild)"
fi
echo "Chạy: open $APP"
