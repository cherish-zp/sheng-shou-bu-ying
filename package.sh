#!/bin/bash
#
# Packages 圣手捕影 into an installable DMG (drag-to-Applications).
# Builds with Xcode automatic signing, then creates dist/圣手捕影-<version>.dmg.
#
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="圣手捕影"

# 清理历史残留的可执行副本，避免 Spotlight 索引到与正式安装同名的旧版 app
rm -rf build/${APP_NAME}.app
# 更名迁移：清除旧名 mac_tool_pro.app 的正式安装副本与构建残留（一次执行后为空操作）
rm -rf "/Applications/mac_tool_pro.app" build/mac_tool_pro.app
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-77SQ3JU8MG}"
DERIVED="build/DerivedData"
APP="$DERIVED/Build/Products/Release/${APP_NAME}.app"

# 签名模式：默认本地自动签名（team 证书）；SIGN_MODE=ci 时 ad-hoc（GitHub Actions
# runner 上无团队证书，产物未公证，用户首次打开需右键 → 打开）
if [ "${SIGN_MODE:-local}" = "ci" ]; then
    SIGN_ARGS=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=NO)
    echo "▸ Xcode build (CI ad-hoc signing)..."
else
    SIGN_ARGS=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CODE_SIGN_STYLE=Automatic)
    echo "▸ Xcode build (automatic signing, team $DEVELOPMENT_TEAM)..."
fi
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project mac_tool_pro.xcodeproj -scheme mac_tool_pro \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED" \
    "${SIGN_ARGS[@]}" \
    clean build >/tmp/shengshoubuying_build.log 2>&1

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG_DIR="dist"
DMG="${DMG_DIR}/${APP_NAME}-${VERSION}.dmg"

echo "▸ Verifying code signature..."
codesign --verify --verbose=4 "$APP" >/dev/null 2>&1 || { echo "✗ Signature verification failed"; exit 1; }

echo "▸ Staging DMG contents (app + Applications link)..."
STAGE="$(mktemp -d)"
ditto "$APP" "$STAGE/${APP_NAME}.app"
ln -s /Applications "$STAGE/Applications"

echo "▸ Creating DMG..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "▸ Verifying DMG..."
hdiutil verify "$DMG" >/dev/null
MNT="/tmp/mtg_${APP_NAME}_$$"
mkdir -p "$MNT"
hdiutil attach -nobrowse -mountpoint "$MNT" "$DMG" >/dev/null
echo "  DMG contents:"; ls -1 "$MNT" | sed 's/^/    /'
hdiutil detach "$MNT" >/dev/null
rmdir "$MNT" 2>/dev/null || true

echo "✓ Packaged: $(pwd)/$DMG"
echo "  Size: $(du -h "$DMG" | cut -f1)"

# 阻止 Spotlight 索引构建产物目录，避免搜索出现多个同名 app
touch build/.metadata_never_index build/DerivedData/.metadata_never_index 2>/dev/null || true
# 同步清理 Xcode GUI 默认 DerivedData 中可能残留的同名 app（含更名前的旧名）
for name in "${APP_NAME}" "mac_tool_pro"; do
    find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 5 -name "${name}.app" -type d -prune -exec rm -rf {} + 2>/dev/null || true
done
