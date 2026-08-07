#!/bin/bash
# 测试脚本：单元测试 + UI 测试
set -euo pipefail

echo "==> Running tests"
xcodebuild test \
    -scheme Notepad \
    -destination 'platform=macOS' \
    -resultBundlePath build/TestResults.xcresult
