#!/bin/bash
# 发布打包脚本：Release 构建 → 签名 → 公证 → 装订（或 --unsigned 未签名 DMG）
# 详细流程见 06_RELEASE.md
set -euo pipefail

cd "$(dirname "$0")/.."

ARCHIVE_PATH="build/Notepad.xcarchive"
EXPORT_PATH="build/Release"
UNSIGNED=""
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' 'Notepad/Supporting Files/Info.plist')"

# 解析参数
for arg in "$@"; do
    case "$arg" in
        --unsigned) UNSIGNED="1" ;;
        -h|--help)
            echo "用法: $0 [--unsigned]"
            echo "  --unsigned  跳过签名/公证，产出未签名 DMG（开源 CI 发布用）"
            exit 0
            ;;
        *) echo "未知参数: $arg" >&2; exit 1 ;;
    esac
done

echo "==> Archiving (Release v$VERSION)"
xcodebuild -scheme Notepad \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    ARCHS="x86_64 arm64" \
    ONLY_ACTIVE_ARCH=NO \
    archive

if [ "$UNSIGNED" = "1" ]; then
    echo "==> 未签名模式：直接取构建产物打包 DMG（跳过签名/公证）"
    APP_PATH="$EXPORT_PATH/Notepad.app"
    rm -rf "$APP_PATH" "$EXPORT_PATH/Notepad-$VERSION.dmg"
    mkdir -p "$EXPORT_PATH"
    cp -R "$ARCHIVE_PATH/Products/Applications/Notepad.app" "$APP_PATH"
    # 移除归档时的签名（ad-hoc 重签，保证 AppKit 资源正确）
    codesign --force --sign - "$APP_PATH"
    hdiutil create -srcfolder "$APP_PATH" \
        -volname "Notepad" -format UDZO \
        -o "$EXPORT_PATH/Notepad-$VERSION.dmg"
    echo "==> 完成: $EXPORT_PATH/Notepad-$VERSION.dmg"
    echo "    注意：未签名 DMG 首次打开需右键 → 打开（Gatekeeper）"
    exit 0
fi

echo "==> Exporting"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist Scripts/ExportOptions.plist

echo "==> 下一步：公证与装订（需配置 Apple ID / Team ID，见 06_RELEASE.md）"
echo "    xcrun notarytool submit ..."
echo "    xcrun stapler staple $EXPORT_PATH/Notepad.app"
