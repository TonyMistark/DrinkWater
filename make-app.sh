#!/bin/zsh
# DrinkWater.app 构建脚本
# 用法：./make-app.sh [输出目录，默认 ./dist]

set -euo pipefail
cd "$(dirname "$0")"

OUT_DIR="${1:-dist}"
APP_NAME="DrinkWater"
DISPLAY_NAME="喝水提醒"
BUNDLE_ID="cn.ice.drinkwater"
VERSION="${DW_VERSION:-0.2.0}"

echo "── 1/4 release 编译…"
swift build -c release --disable-sandbox --product "$APP_NAME"
BIN=".build/release/$APP_NAME"

echo "── 2/4 组装 $APP_NAME.app…"
APP="$OUT_DIR/$APP_NAME.app"
mkdir -p "$OUT_DIR"
: > "$OUT_DIR/.metadata_never_index"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

ICON="Assets/AppIcon.icns"
if [[ -f "$ICON" ]]; then
    cp "$ICON" "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$DISPLAY_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>         <string>$VERSION</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.healthcare-fitness</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSSupportsAutomaticTermination</key> <false/>
    <key>NSSupportsSuddenTermination</key>   <false/>
    <!-- 允许连接自建的 http 推送服务（ntfy / 内网 Webhook） -->
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key> <true/>
    </dict>
</dict>
</plist>
PLIST

if [[ -f "$ICON" ]]; then
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" >/dev/null
fi

echo "── 3/4 签名…"
IDENTITY="${DW_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITY=$(security find-identity -v -p codesigning | grep -oE '"[^"]+"' | head -1 | tr -d '"') || true
fi
if [[ -n "$IDENTITY" && "$IDENTITY" != "-" ]]; then
    codesign --force --options runtime --sign "$IDENTITY" "$APP"
    echo "   已用 $IDENTITY 签名"
else
    codesign --force --sign - "$APP"
    echo "   ad-hoc 签名"
fi

# 注册到 LaunchServices，系统通知才能正确显示应用名
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[[ -x "$LSREGISTER" ]] && "$LSREGISTER" -f "$APP" || true

echo "── 4/4 校验…"
codesign --verify --verbose "$APP" 2>&1 | tail -1

DMG="$OUT_DIR/drinkwater-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "$DISPLAY_NAME $VERSION" -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null
echo ""
echo "✓ 完成：$APP（版本 $VERSION）"
echo "  DMG：$DMG"
