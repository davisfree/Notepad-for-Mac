#!/bin/bash
# 构建脚本（Debug / Release），产物输出到 build/dd/Build/Products/<配置>/Notepad.app
set -euo pipefail

CONFIGURATION="${1:-Debug}"

echo "==> Building Notepad ($CONFIGURATION, Universal Binary)"
xcodebuild -scheme Notepad \
    -configuration "$CONFIGURATION" \
    -derivedDataPath build/dd \
    ARCHS="x86_64 arm64" \
    ONLY_ACTIVE_ARCH=NO \
    build
echo "==> 产物: build/dd/Build/Products/$CONFIGURATION/Notepad.app"
