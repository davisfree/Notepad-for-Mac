# 架构设计

> 待补充。权威来源见仓库上层目录的 `01_TECH_SPEC.md` 第 2 节（系统架构图）与 `04_MODULE_API.md`（模块接口契约）。

## 分层

```
Presentation Layer   → Notepad/UI, Notepad/Editor（视图部分）
Business Logic Layer → Notepad/Document, Notepad/Services
Data & Storage Layer → Notepad/Preferences, Utilities
```

依赖方向（见 `08_KIMI_INSTRUCTION.md` 第 3 节）：

```
App → Document → Editor → UI → Utilities
  ↓       ↓         ↓      ↓
Preferences ← Services ←──┘
```
