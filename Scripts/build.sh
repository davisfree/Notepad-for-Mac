#!/bin/bash
# 构建脚本（Debug / Release），产物输出到 build/<配置>/Notepad.app
# （产物位置由 project.yml 的 SYMROOT 统一控制）
set -euo pipefail

CONFIGURATION="${1:-Debug}"

echo "==> Building Notepad ($CONFIGURATION, Universal Binary)"
xcodebuild -scheme Notepad \
    -configuration "$CONFIGURATION" \
    ARCHS="x86_64 arm64" \
    ONLY_ACTIVE_ARCH=NO \
    build
echo "==> 产物: build/$CONFIGURATION/Notepad.app"
