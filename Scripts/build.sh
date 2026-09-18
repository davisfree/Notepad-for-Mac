#!/bin/bash
# 构建脚本（Debug / Release），产物输出到仓库 build/ 目录
# （产物位置由 project.yml 的 SYMROOT + CONFIGURATION_BUILD_DIR 统一控制）
set -euo pipefail

CONFIGURATION="${1:-Debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Building Notepad ($CONFIGURATION, Universal Binary)"
xcodebuild -scheme Notepad \
    -configuration "$CONFIGURATION" \
    ARCHS="x86_64 arm64" \
    ONLY_ACTIVE_ARCH=NO \
    build
echo "==> 产物: $ROOT/build/Notepad.app"
