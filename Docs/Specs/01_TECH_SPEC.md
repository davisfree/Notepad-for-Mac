# Notepad for macOS — 技术规格书 (TECH_SPEC)
> **版本**：v1.1  
> **日期**：2026-08-02  
> **对应 PRD**：`PRD_Notepad_macOS.md`  
> **v1.1 修订**：编码检测弃用私有库 libicucore，改为自研 BOM + 启发式方案；标签页选型改为自绘标签栏；明确自动保存开关的保存管线；包体积指标按"核心/完整版"拆分；补全编码清单、性能指标与沙盒持久访问说明

---

## 1. 技术选型决策

### 1.1 核心栈

| 层级     | 技术                         | 版本      | 决策理由                                            |
| -------- | ---------------------------- | --------- | --------------------------------------------------- |
| 语言     | Swift                        | 5.9+      | 原生性能，直接调用 AppKit/Cocoa                     |
| UI 框架  | AppKit (NS*)                 | macOS 12+ | 原生 macOS 控件，完美匹配系统行为                   |
| 文本引擎 | NSTextView + NSLayoutManager | 系统内置  | 系统级文本渲染，支持大文件虚拟化                    |
| 架构模式 | MVC + NSDocument             | 系统内置  | 利用 macOS 原生文档架构，自动获得版本管理           |
| 编码检测 | 自研 BOM + 启发式（Foundation） | 系统内置 | libicucore 为 Apple 私有库，App Store 不可用；自研零依赖，准确率不足时备选开源 ICU |
| 更新机制 | Sparkle 2.x                  | 2.5+      | macOS 事实标准的自动更新框架（仅直发/Homebrew 渠道） |
| 崩溃报告 | Sentry                       | SPM 引入  | 线上崩溃监控；懒加载初始化，不阻塞启动              |

### 1.2 不采用的方案及原因

| 方案         | 放弃原因                                                     |
| ------------ | ------------------------------------------------------------ |
| Electron     | 包体积 > 100MB，启动慢，不符合"极致轻量"定位                 |
| Tauri        | 跨平台优势对本项目无意义，Rust 绑定增加复杂度                |
| SwiftUI      | macOS 12 下 SwiftUI 文本编辑能力弱于 AppKit，且 NSTextView 桥接复杂 |
| 自研文本引擎 | 成本过高，NSTextView 已满足所有需求                          |
| libicucore（私有 ICU） | Apple 私有库，App Store 审核拒收风险；改用 Foundation + 自研启发式 |
| Crashlytics  | 依赖 Firebase SDK，体积数 MB，违背轻量定位；崩溃监控统一用 Sentry |
| NSTabView / NSWindowTabbing | 无可拖拽标签 UI / 交互与 Win11 差异大；标签页改自绘（见 3.4） |

---

## 2. 系统架构

```
┌─────────────────────────────────────────────────────────────┐
│                      Presentation Layer                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ MainWindow  │  │ NPTabBarView│  │ StatusBarView       │  │
│  │ (NSWindow)  │  │ (自绘NSView)│  │ (NSView + NSStack)  │  │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘  │
│         └─────────────────┴────────────────────┘            │
│                              │                              │
│  ┌───────────────────────────┴───────────────────────────┐  │
│  │              EditorView (NSTextView)                  │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐   │  │
│  │  │ FindBar     │  │ ReplaceBar  │  │ GoToLine    │   │  │
│  │  │ (NSView)    │  │ (NSView)    │  │ (NSPanel)   │   │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘   │  │
│  └───────────────────────────────────────────────────────┘  │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────┴──────────────────────────────────┐
│                      Business Logic Layer                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ Document    │  │ Encoding    │  │ SessionManager      │  │
│  │ Controller  │  │ Manager     │  │ (标签/窗口状态)      │  │
│  │ (NSDocument)│  │ (自研检测)   │  │                     │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ LineEnding  │  │ ThemeEngine │  │ PrintManager        │  │
│  │ Manager     │  │ (外观管理)   │  │ (NSPrintOperation)  │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────┴──────────────────────────────────┐
│                      Data & Storage Layer                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ UserPrefs   │  │ FileI/O     │  │ AutoSaveBackup      │  │
│  │(UserDefaults)│  │(NSFileCoord)│  │ (NPBackupService)   │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. 关键模块设计

### 3.1 Document Controller（NSDocument 子类）

```swift
class NPTextDocument: NSDocument {
    // 核心属性
    var textContent: String = ""
    var encoding: String.Encoding = .utf8
    var lineEnding: LineEnding = .lf
    var hasBOM: Bool = false

    // 重写读写方法，实现编码/换行符控制
    override func read(from data: Data, ofType typeName: String) throws
    override func data(ofType typeName: String) throws -> Data
}
```

**设计要点**：
- 继承 `NSDocument` 自动获得：版本浏览、iCloud 支持、窗口/撤销管理
- 重写 `read(from:ofType:)` 实现编码检测与换行符识别（检测逻辑委托 `NPEncodingManager`，接口见 `04_MODULE_API.md` 1.1）
- 重写 `data(ofType:)` 实现按当前编码/换行符格式输出
- 自动保存为文档级开关，保存管线见 3.5

### 3.2 编码检测引擎

**决策**：不链接 `libicucore`（Apple 私有库，App Store 审核拒收风险）。检测分两阶段自研实现，对应 `04_MODULE_API.md` 的 `NPDefaultEncodingDetector`：

```swift
struct NPDefaultEncodingDetector: NPEncodingDetector {
    /// 阶段 1 — BOM 检测：
    ///   UTF-8 / UTF-16 LE·BE / UTF-32 LE·BE 仅通过 BOM 判定（内容分析不可靠）
    /// 阶段 2 — 无 BOM 内容启发式（优先级对齐 PRD FR-010：UTF-8 > GBK > ANSI）：
    ///   1. UTF-8 严格校验，存在非法序列即排除
    ///   2. 双字节区间统计区分 GB18030（超集，覆盖 GBK/GB2312）与 Big5
    ///   3. 均不匹配时回退 Windows-1252（西方语言兜底）
    func detect(from data: Data) throws -> NPEncodingDetectionResult
}
```

**设计要点**：
- 支持编码全集对齐 PRD FR-010：UTF-8（带/不带 BOM）、UTF-16 LE/BE、UTF-32 LE/BE、Windows-1252、GB2312/GBK/GB18030、Big5
- GB18030 无 `String.Encoding` 内置常量，需经
  `String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))` 构造
- 检测置信度低于阈值时抛出 `NPEncodingError.undetectable`，UI 层引导用户手动选择编码重新打开（PRD FR-010）
- **回退预案**：若 `05_TEST_PLAN.md` 的多语言样本测试准确率不达标，再以 SPM 引入开源 ICU（unicode-org/icu）替换检测器实现——协议隔离（`NPEncodingDetector`）保证可替换，但需重新评估包体积指标

### 3.3 大文件处理策略

| 文件大小   | 策略                                                         |
| ---------- | ------------------------------------------------------------ |
| < 1MB      | 直接加载到 NSTextStorage                                     |
| 1MB - 10MB | 后台线程解析编码，主线程渐进渲染；利用 NSLayoutManager 惰性排版 |
| > 10MB     | 提示用户后以**只读模式整体加载**（PRD FR-001）；不做分页/mmap 加载——避免与 1.2 节"放弃自研文本引擎"的决策冲突 |

### 3.4 标签页实现

**决策**：自绘标签栏（`NPTabBarView`，`NSView` 子类），不采用 `NSTabView`（无可拖拽标签 UI）与 `NSWindowTabbing`（系统原生标签交互与 Win11 差异大）。

**设计要点**：
- 支撑 PRD FR-002 全部交互：拖拽排序、拖出窗口形成新窗口、右键菜单（关闭/关闭其他/关闭右侧/复制标签/在 Finder 中显示）、未保存圆点 `●`；接口契约见 `04_MODULE_API.md` 3.2
- 窗口结构：**一个窗口聚合多个 `NPTextDocument`**。每个标签仍是独立 `NSDocument` 实例——独立撤销栈、脏状态、自动保存（PRD FR-005）；窗口控制器负责标签与文档的映射及活动文档切换
- `NSDocumentController` 仍统一管理全部文档实例（最近文件、无窗口新建等系统行为不变）

### 3.5 自动保存与崩溃恢复管线

PRD FR-003 要求自动保存为**可开关**（默认开启），5.3 要求崩溃丢失不超过 1 秒。保存行为按文档类型拆分：

| 场景               | 开关 ON                                          | 开关 OFF                          |
| ------------------ | ------------------------------------------------ | --------------------------------- |
| 已存盘的文件       | 编辑后自动写回原文件（NSDocument 保存管线）      | 仅更新脏状态，关闭时弹保存确认    |
| 未命名文档         | 持续写入会话备份，重启后原样恢复                 | 同左（备份不受开关影响）          |
| 关闭标签/窗口      | 无确认直接关闭                                   | 有未保存更改时弹确认面板          |

**设计要点**：
- `NPBackupService` 以 **≤ 1 秒节流**将编辑内容写入会话备份（含未命名文档与光标位置，备份格式见 `04_MODULE_API.md` 的 `NPBackupItem`），保证 PRD 5.3 的崩溃恢复指标——该机制与自动保存开关**无关**，始终生效
- 开关只控制"是否自动写回原文件"，实现上覆写 `NSDocument` 的变更跟踪（`updateChangeCount` / `isDocumentEdited`），不依赖 `autosavesInPlace` 的类型级开关
- 启动时通过 `recoverableItems()` 恢复上次会话的全部标签页、内容与光标位置（PRD FR-003）

---

## 4. 性能指标与优化策略

| 指标                     | 目标值  | 优化手段                            |
| ------------------------ | ------- | ----------------------------------- |
| 冷启动（Apple Silicon）  | < 500ms | 延迟加载非核心模块，Sentry 懒初始化 |
| 冷启动（Intel）          | < 800ms | 同上                                |
| 热启动                   | < 200ms | 窗口/文档控制器复用                 |
| 1MB 文件打开             | < 1s    | 后台线程解析编码                    |
| 10MB 文件打开            | < 3s    | 后台线程解析编码，主线程渐进渲染    |
| 打字延迟                 | < 16ms  | NSTextView 原生输入，无额外处理层   |
| 内存占用（空文档）       | < 50MB  | 空文档时释放未使用缓存              |
| 内存占用（10 标签页）    | < 150MB | 非活动标签释放渲染缓存              |
| 包体积（核心）           | < 5MB   | 仅链接必要系统框架，无嵌入式资源    |
| 包体积（完整直发版）     | < 15MB  | 含 Sparkle + Sentry 的上限          |

> 注：原"< 5MB"指标在引入 Sparkle（约 2MB）与 Sentry（约 3–8MB）后不可达，拆分为两档；App Store 版不含 Sparkle，体积介于两档之间。

---

## 5. 安全与隐私

- **沙盒**：App Store 版本启用 App Sandbox，仅申请 `user-selected-file-read/write` 权限
- **持久访问**：最近文件（FR-008）与会话恢复（FR-003）在沙盒下使用 security-scoped bookmark 保存文件访问权限，重启后可直接重新打开
- **隐私**：不上传任何文件内容至服务器
- **自动保存**：会话备份仅存储于本地沙盒容器内
- **崩溃日志**：匿名化后上传，不含文件路径与内容片段

---

## 6. 构建与部署

### 6.1 Xcode 项目配置

```
Deployment Target: macOS 12.0
Architectures: $(ARCHS_STANDARD)  // Universal Binary (x86_64 + arm64)
Code Signing: Apple Development / Distribution
Sandbox: YES (App Store) / NO (Direct Distribution)
Hardened Runtime: YES
```

### 6.2 构建脚本

```bash
# 开发构建
xcodebuild -scheme Notepad -configuration Debug

# 发布构建（签名 + 公证）
xcodebuild -scheme Notepad -configuration Release
# → 生成 Notepad.app
# → codesign --deep --force --verify
# → xcrun notarytool submit (Apple 公证)
# → stapler staple Notepad.app
```

### 6.3 分发渠道

| 渠道      | 包格式        | 签名要求    | 更新方式           |
| --------- | ------------- | ----------- | ------------------ |
| App Store | `.app` + 归档 | 严格沙盒    | App Store 自动更新 |
| 官网直发  | `.dmg`        | 公证 + 门禁 | Sparkle 自动更新   |
| Homebrew  | `.zip`        | 公证 + 门禁（同直发，Gatekeeper 要求） | brew upgrade       |

> **条件编译约束**：Sparkle 及 `NPUpdateService` 仅链接进直发/Homebrew 构建，App Store 构建通过编译条件 `#if !APP_STORE` 整体剔除（Apple 禁止应用内自更新；接口约定见 `04_MODULE_API.md` 5.2）。

---

## 7. 依赖清单

### 7.1 系统框架（无需引入）

- `AppKit` — UI 与窗口管理
- `Foundation` — 基础类型与文件 I/O
- `Combine` — 偏好设置观察（`@Published`，见 8.2）

### 7.2 第三方库（SPM）

| 库名    | 用途     | 引入方式 | 约束                             |
| ------- | -------- | -------- | -------------------------------- |
| Sparkle | 自动更新 | SPM      | 仅直发/Homebrew 构建（`#if !APP_STORE`） |
| Sentry  | 崩溃监控 | SPM      | 懒加载初始化，不阻塞冷启动       |

> 备选：编码检测准确率不达标时，以 SPM 引入开源 ICU（unicode-org/icu）替换 `NPDefaultEncodingDetector`，需同步重估 4 中的包体积指标。

### 7.3 开发工具

- Xcode 15.0+
- SwiftLint（代码规范检查）
- SwiftFormat（自动格式化）

---

## 8. 接口契约

### 8.1 模块间通信

采用 Delegate + Notification 模式，禁止直接持有其他模块实例：

```swift
// 示例：EditorView → Document 的编辑通知
protocol NPEditorDelegate: AnyObject {
    func editorDidChangeContent(_ editor: NPEditorView)
    func editorDidChangeSelection(_ editor: NPEditorView)
}

// 通知名称与 userInfo 键统一由常量定义（04_MODULE_API.md 第 6 节）
// 示例：状态栏订阅缩放变化
NotificationCenter.default.addObserver(
    self, selector: #selector(handleZoomChange(_:)),
    name: NPNotificationNames.zoomLevelDidChange, object: nil
)
```

### 8.2 配置热更新

所有用户偏好变更立即生效、无需重启。**存储层**使用 `UserDefaults`，**观察层**使用 Combine `@Published`（权威接口定义见 `04_MODULE_API.md` 第 4 节，本文不再重复）：

```swift
@MainActor
final class NPPreferences: ObservableObject {
    @Published var theme: NPTheme = .system
    @Published var font: NSFont = .systemFont(ofSize: 12)
    @Published var autoWrap: Bool = true
    // ...
}
```

> 注：Combine 可在纯 AppKit 工程中使用，不引入 SwiftUI 依赖，与 1.2 节"不采用 SwiftUI"的决策不冲突。

> 完整的模块接口契约（编码管理器、查找控制器、标签栏、备份服务等）以 `04_MODULE_API.md` 为唯一依据，本文不再重复定义。
