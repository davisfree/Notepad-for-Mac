#!/bin/bash
# 代码规范检查（SwiftLint）
set -euo pipefail

if ! command -v swiftlint >/dev/null 2>&1; then
    echo "ERROR: swiftlint 未安装，请执行 brew install swiftlint" >&2
    exit 1
fi

echo "==> SwiftLint"
swiftlint lint --strict
