#!/bin/bash
# 无 Xcode 环境下的开发构建：swiftc 直接编译并组装 Notepad.app
# 产出 build/Notepad.app（ad-hoc 签名，仅供本机开发调试）
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Notepad.app"

echo "==> 编译（swiftc 直编全部源码）"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/en.lproj"
# shellcheck disable=SC2046
swiftc -swift-version 5 -o "$APP/Contents/MacOS/Notepad" $(find Notepad -name '*.swift')

echo "==> 组装 bundle"
sed -e 's/\$(EXECUTABLE_NAME)/Notepad/g' \
    -e 's/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.notepadmac.Notepad/g' \
    -e 's/\$(PRODUCT_NAME)/Notepad/g' \
    -e 's/\$(MACOSX_DEPLOYMENT_TARGET)/12.0/g' \
    "Notepad/Supporting Files/Info.plist" > "$APP/Contents/Info.plist"

for lang in en zh-Hans zh-Hant; do
    if [ -d "Notepad/Resources/$lang.lproj" ]; then
        cp -R "Notepad/Resources/$lang.lproj" "$APP/Contents/Resources/"
    fi
done
[ -f Notepad/Resources/Credits.rtf ] && cp Notepad/Resources/Credits.rtf "$APP/Contents/Resources/"
[ -f Notepad/Resources/AppIcon.icns ] && cp Notepad/Resources/AppIcon.icns "$APP/Contents/Resources/"

echo "==> ad-hoc 签名"
codesign --force --sign - "$APP"
codesign -v "$APP"

echo "==> 完成: $APP"
echo "    运行: open $APP"
