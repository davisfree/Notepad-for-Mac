#!/bin/bash
# 构建脚本（Debug / Release）
set -euo pipefail

CONFIGURATION="${1:-Debug}"

echo "==> Building Notepad ($CONFIGURATION, Universal Binary)"
xcodebuild -scheme Notepad \
    -configuration "$CONFIGURATION" \
    ARCHS="x86_64 arm64" \
    ONLY_ACTIVE_ARCH=NO \
    build
