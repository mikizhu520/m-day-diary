#!/bin/bash
# 构建 MDay（原「日迹」）macOS 原生应用
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_SRC="$ROOT/app"
DIST="$ROOT/dist"
APP="$DIST/MDay.app"
BUNDLE_ID="com.meiling.riji"
# 版本号。改这里的同时要改 Models.swift 里的 AppInfo.version，
# 否则「关于」页显示的和系统看到的不一致。
VERSION="0.0.1"

echo "▸ 编译 Swift（release）…"
cd "$APP_SRC"
# --disable-sandbox：某些环境下 SwiftPM 内部调 sandbox-exec 会报
# "sandbox_apply: Operation not permitted" 导致 Invalid manifest
swift build -c release --disable-sandbox
BIN_PATH="$(swift build -c release --disable-sandbox --show-bin-path)/RiJi"

echo "▸ 组装 .app …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/RiJi"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MDay</string>
    <key>CFBundleDisplayName</key><string>MDay</string>
    <key>CFBundleExecutable</key><string>RiJi</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MDay · 本地优先的 Markdown 日记本 · Miki Zhu</string>
    <key>NSFaceIDUsageDescription</key><string>用面容 ID 快速解锁你的日记</string>
    <key>CFBundleLocalizations</key><array><string>zh_CN</string></array>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
PLIST

echo "▸ 生成图标 …"
ICON_TMP="$(mktemp -d)"
swiftc -O "$ROOT/tools/gen_icon.swift" -o "$ICON_TMP/genicon"
"$ICON_TMP/genicon" "$ICON_TMP/icon_1024.png" >/dev/null

ICONSET="$ICON_TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
    set -- $spec
    sips -z "$1" "$1" "$ICON_TMP/icon_1024.png" --out "$ICONSET/icon_$2.png" >/dev/null 2>&1
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICON_TMP"

echo "▸ 签名（ad-hoc）…"
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "  （签名跳过，不影响本机运行）"

echo "▸ 完成：$APP"
