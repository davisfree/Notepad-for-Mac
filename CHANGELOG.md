# Changelog

本项目遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [1.0.2] - 2026-08-21

### Added
- 帮助 → 查看帮助：新增应用内帮助窗口 `NPHelpWindowController`（只读 Markdown 渲染，窗口关闭仅隐藏复用），正文为三语本地化资源 `Resources/<locale>.lproj/Help.md`，经 `NPHelpContent` 加载（Bundle 可注入）；菜单项由 `NSApp showHelp:` 改接 `AppDelegate.showHelp:`，附 `NPHelpContentTests` 与帮助菜单结构断言
- 新增 `NPMarkdownRenderer` 极简 Markdown 渲染器（标题/列表/加粗/行内代码 → 真实字体属性；`AttributedString(markdown:)` 的 presentationIntent 语义属性 AppKit 不解析）

## [1.0.1] - 2026-08-09

### Added
- 偏好设置窗口（⌘,）：`NPPreferencesWindowController` + 通用/编辑器偏好面板，字体等全局项变更经 `preferencesDidChange` 通知实时同步已开窗口
- 新增 `NPLanguage` 语言模型及偏好面板/语言切换相关测试

### Changed
- 界面语言切换迁移至偏好面板（`NPLanguage.apply`，重启后生效），移除"显示语言"子菜单
- `NPBackupService` 备份缓存垃圾清理增强：`recoverableRecords` 只返回有效记录，新增 `pruneInvalidBackupFiles(keeping:)` 清理超期/临时残留/孤儿/损坏文件；`writeBackToOriginal` 改非原子写，消除沙盒原子写在用户目录遗留的 `.sb-*` 临时文件
- 工程适配 Xcode 26：测试目标启用 `GENERATE_INFOPLIST_FILE`，解除与 App 目标的依赖循环；AppKit 相关测试类标注 `@MainActor`（Swift 6 严格并发）

### Fixed
- 修复退出弹保存提示：退出流程先落盘会话备份并统一清脏，不再弹"审查未保存文稿"警报与逐文档保存面板（未保存状态由磁盘备份承载，下次启动经会话恢复还原并重新标脏）
- 修复界面显示语言切换后重启无效、跟随系统不生效的问题
- 修复重启后窗口数累积：关窗即删备份、退出时清理残留

## [1.0.0] - 2026-08-07

### Added
- 项目初始化：按 `07_PROJECT_STRUCTURE.md` 建立标准目录结构
- Document 模块：`NPEncodingManager`（两阶段编码检测：BOM → 内容启发式，支持 UTF-8/16/32、GB18030、Big5、Windows-1252）、`NPLineEndingManager`（换行符检测与归一）
- Document 类型：`NPLineEnding`、`NPEncodingDetectionResult`、`NPEncodingError`、`NPError`
- `NPTextDocument` 对齐 `04_MODULE_API.md` 契约：编码/换行符读写管线、`changeEncoding(to:)`、`changeLineEnding(to:)`
- 单元测试：UT-ENC-001 ~ UT-ENC-014、UT-LE-001 ~ UT-LE-006、UT-DOC-001 ~ UT-DOC-003
- Editor 模块：`NPEditorView`（行列计算、自动换行、字体缩放 10%–500%、查找高亮、转到行、F5 时间戳）、`NPTextView`（SF Mono 12pt、8pt 内边距、复刻配色随外观切换）、`NPEditorDelegate`
- 查找替换：`NPFindController`（默认不区分大小写、回绕、正则，无 UI 依赖可后台执行）、`NPReplaceController`（从后往前替换避免范围偏移）、`NPFindOptions`、`NPFindError`
- `NPEditorController`：协调编辑器与文档（内容回写、脏状态同步、后台查找回主线程高亮）
- `NPTextDocument.makeWindowControllers` 装入 `NPEditorView`，App 可实际编辑
- `NPNotificationNames` 通知常量（`04_MODULE_API.md` 6.1）
- 单元测试：UT-FIND-001 ~ UT-FIND-006、替换范围偏移回归、行列计算
- 主菜单：`NPMenuBuilder`（spec 数据驱动）按 PRD 4.1/4.2 全量构建六个菜单，"检查更新…"按 `#if !APP_STORE` 条件编译；菜单文案三语本地化（en/zh-Hans/zh-Hant）
- 窗口装配：`NPWindowFactory` + `NPEditorWindowController`（UI 层），`NPTextDocument` 经闭包注入调用，消除 Document → Editor/UI 逆向依赖；窗口标题 `displayName - Notepad`、最小尺寸 400×300
- `NPEditorView` 响应链菜单动作：F5 时间戳、查找/替换栏钩子、自动换行（含勾选状态）、缩放 ⌘+/⌘-/⌘0（步进 10%）
- `AppDelegate`：安装主菜单、文件/应用级动作接线、状态栏/主题/始终在最前的 `validateMenuItem` 状态管理、"打开最近使用的"动态重建
- `NPConstants`：菜单 tag、菜单标识、缩放步进常量

### Changed
- `NPTextDocument.makeWindowControllers` 改为闭包注入装配（原直接引用 Editor 层类型）
- `main.swift` 以 `MainActor.assumeIsolated` 包裹入口（适配 Swift 6.3 编译器隔离检查）

### Added
- Preferences 模块：`NPPreferences`（UserDefaults 持久化 + Combine @Published，默认值对齐 PRD 7.1，export/import JSON）、`NPTheme`、`NPPreferencesError`
- 主题：`NPThemeManager`（NSApp 级外观应用 + `NPThemeDidChange` 通知）、`NPColorPalette`（02 色值动态颜色集中定义）
- 接线：AppDelegate 占位状态移除（主题/状态栏勾选读偏好，主题动作走 `NPThemeManager.apply`）；`NPTextView` 配色改走 `NPColorPalette`、字体面板选择回写偏好；新窗口按偏好应用自动换行/字体/缩放默认值
- 状态栏：`NPStatusBarView`（22pt，Ln/Col ｜ 缩放% ｜ 换行符 ｜ 编码，PRD FR-012 顺序）、`NPStatusBarButton`（hover 效果）、`NPStatusBarController`（点击弹出缩放/换行符/编码菜单，回写文档；编码失败弹错）、`NPStatusBarFormatter`（文案纯函数）
- `NPTextDocument` 发出 `documentEncodingDidChange`/`documentLineEndingDidChange` 通知（04 §6.2，userInfo 按桥接规则）
- `NPEditorController` 行列/缩放闭包回调（Editor 层不依赖 UI 层）；窗口装配编辑区 + 状态栏垂直布局，状态栏可见性绑定偏好（⌘/ 即时生效）
- 查找栏 UI：`NPFindBarView`（毛玻璃悬浮编辑区顶部，44/76pt，匹配统计"3/17"/"未找到"）、`NPFindBarController`（委托 → `NPEditorController`；FindBar 与 Editor 同层经协议/闭包通信）；⌘F/⌥⌘F/⌘G/⇧⌘G 全接通，输入实时查找高亮，关闭清高亮
- 查找导航：`NPEditorController.findNextMatch/findPreviousMatch`（回绕，无查找词沿用上次）；匹配统计经 `onMatchesDidChange` 回流查找栏；查找高亮配色对齐 02 §5.2（黄底 + 橙色当前匹配）
- 转到行：`NPGoToLineController` + `NPGoToLinePanel`（非模态浮动 NSPanel，行号校验夹取 1...maxLine，Enter/Esc，预填当前行）；接通菜单 ⌃G 与状态栏 Ln/Col 点击

### Fixed
- `NPEditorView` 底层 `NSTextView` 以 `init(frame:textContainer: nil)` 创建时文本系统未建立（`string` 赋值静默失败、编辑器无内容），改为显式装配 `NSTextStorage`/`NSLayoutManager`/`NSTextContainer`（由第六轮 headless 流程测试发现）
- 英文本地化从 `Resources/Localizable.strings` 迁入 `Resources/en.lproj/`（bundle 根级 strings 不会被系统加载；`07_PROJECT_STRUCTURE.md` 已同步修正）
- 启动弹窗"未能创建文稿"：macOS 26 下 `swiftc` 直编 bundle 的 `NSDocumentController` 无法解析 Info.plist 中的 `NSDocumentClass`，新增 `NPDocumentController` 子类显式提供类型映射（`AppDelegate.init` 中首个实例化，成为 shared controller）

### Added
- `Scripts/dev-build.sh`：无 Xcode 环境下 swiftc 直编 + 组装 + ad-hoc 签名 `build/Notepad.app` 的开发构建脚本
- 多标签页：`NPTabBarView`（32pt，拖拽排序 + 2pt 插入指示线 + 20pt 拖出判定，右键菜单五项）、`NPTabItemView`（未保存蓝点/悬停关闭/选中态）、`NPTabBarController`（关闭确认流程、批量顺序关闭、复制标签）、`NPTabGroupModel`（纯逻辑）
- 架构：`NPEditorWindowController` 改为标签组容器（一窗口聚合多文档，`document` 指向当前标签文档）；`NPTabWindowManager` 路由（⌘T/打开 → 当前窗口加标签，⌘N → 新窗口，拖出 → 新窗口托管）；`NPTextDocument` 工厂可空返回 + `onDisplayNameChange`/`onEditedStateChange` 回调
- 菜单：⌘W 改为关闭当前标签（最后一个标签关闭即关窗口），视图菜单新增 ⇧⌘]/⇧⌘[ 标签切换
- 打印服务：`NPPrintService`（页面设置面板按文档保留 NSPrintInfo；打印渲染为带页眉页脚的分页视图——页眉文件名居中、页脚"第 X 页 共 Y 页"，使用文档字体、黑字白底）；菜单"页面设置…/打印…"改路由到打印服务并作用于当前标签文档，无文档时菜单项禁用
- 启动出现两个无标题标签：`applicationShouldHandleReopen` 覆写与系统默认行为及状态还原形成竞态，重复创建文档；移除覆写交还系统默认行为
- ⌘N 不创建新窗口：`NSDocumentController.newDocument` 创建过程异步，临时路由标志在工厂执行前被还原，新文档被误路由为当前窗口标签；改为 `makeUntitledDocument` + `openInNewWindow` 确定性路径
- 首次点击 Dock 图标不显示窗口：残留的持久状态（`hasPersistentStateToRestore=1`）抑制启动自动新建文档，还原却又还原不出窗口；禁用 AppKit 窗口状态还原（`NSQuitAlwaysKeepsWindows=false`，会话恢复后续由 NPBackupService 自研）
- 冷启动无窗口/二次点击出现双标签：`NPEditorWindowController.showEntry` 直接给 `document` 属性赋值而不经 `addWindowController` 注册，导致文档无窗口控制器、`showWindows` 空转（窗口创建但永不显示）；同时 `makeUntitledDocument` 在 macOS 26 不再自动纳入 `documents` 跟踪。修复：标签切换改走 `addWindowController`/`removeWindowController` 正式注册；新建文档统一经 `makeTrackedUntitledDocument` 补登记；启动/reopen 新建窗口改为 `openUntitledWindowIfNoDocuments` 确定性路径并停用 `applicationShouldOpenUntitledFile` 默认行为
- 关闭当前选中标签误关整个窗口：`NSDocument.close()` 会连带关闭其 windowControllers 的窗口；`closeTabImmediately` 改为先把文档从共享窗口控制器注销再关闭
- 文件菜单调整（按需求变更）：新建标签页 ⌘N 置于首位、新建窗口 ⇧⌘N 居次；"关闭窗口"改用自定义 action `closeWindowAction:`（内部仍走 performClose），去除 macOS 26 自动配的标准 selector 图标；PRD 4.1/4.2、05 IT-TAB-001 已同步
- 自动保存与会话恢复：`NPBackupService`（≤1s 节流写会话备份，Application Support/Notepad/Backups 下 <UUID>.txt + .json；备份与开关无关始终生效；ON 且已存盘时节流写回原文件保持原编码/换行符/BOM）；`NPBackupItem`/`NPBackupMetadata`
- 关闭/退出行为对齐 01 §3.5：开关 ON 关闭标签/窗口/退出无确认、OFF 保留 canClose 确认流；正常关闭删除备份，退出应用备份保留
- 会话恢复：启动时 `recoverableRecords()` 非空则按窗口归属分组恢复标签（未命名 → 备份内容标脏；已存盘有改动 → 备份内容标脏；无改动 → 原样；原文件丢失 → 退化为未命名），恢复光标位置与备份标识沿用
- 关闭窗口/标签弹"保留文稿"对话框：`NSDocument.close()` 对脏文档会触发系统确认（探针实测挂起），`closeTabImmediately` 改为先落盘待写内容（新增 `flushPendingWrites`）、注销备份、清脏后再关闭；同时修复关闭时尾缘节流窗口内（≤1s）编辑丢失的问题
- 关闭窗口仍弹保存确认（第二轮修复）：系统依据 `window.isDocumentEdited` 在关窗时自行触发确认，先于自定义流程；自动保存 ON 时窗口控制器在标题同步中强制清除该标记（脏状态由会话备份承载，标签圆点已表达）
- 关闭语义按用户规则纠正（对齐 Win11）：直接关闭标签（⌘W/标签按钮）有未保存内容时弹系统确认；关闭窗口（红按钮/⇧⌘W）与退出（⌘Q）一律静默——红按钮改走自定义 action（系统 performClose 对脏文档窗口会先弹确认且抢占所有委托，探针实测），关窗仅"摘除"标签：落盘待写内容、保留磁盘备份与内存文档，Dock 重开原样重建窗口，重启经会话恢复还原；退出前统一落盘并清脏避免系统复查弹窗
- 空未命名标签关闭误提示：会话恢复时空内容也被标脏，且关标签只看脏标记不看内容；恢复改为仅非空内容标脏，关标签对"未修改或空内容"直接放行
- 大文件策略：超过 10MB 的文件提示"将以只读模式打开"（本地化）后只读加载——编辑器 `isEditable=false`、保存抛 `NPError.documentIsReadOnly`；阈值入 `NPConstants.largeFileThreshold`
- Touch Bar（FR-023）：`NPEditorWindowController` 实现 `NSTouchBarDelegate`，默认项 新建/打开/保存/查找/自动换行 + 编辑项 剪切/复制/粘贴/撤销/重做（全部复用菜单 action）
- 快捷指令（FR-024）：`NPShortcutService` + App Intents（macOS 13+，12 优雅降级不注册）；动作 用 Notepad 打开文件 / 创建新文本文件，经闭包注入路由避免 Services→UI 逆向依赖
- 未命名标签保存无 .txt 后缀：`prepareSavePanel` 声明 `allowedContentTypes = [.plainText]` 并显示扩展名，默认补 .txt（允许用户自改其他扩展名，对齐 Win11）
- 支持打开任意扩展名的纯文本文件（PRD FR-001）：`NPConstants.TextTypes` 集中定义受支持 UTI + 扩展名清单（txt/log/bat/cmd/sh/py/js/json/xml/html/md/ini/cfg/csv/yml 等）；`NPDocumentController` 扩展类型映射（UTType 判定 + 显式 UTI + 扩展名）、`makeDocument` 按 URL 扩展名兜底、打开面板并入全部受支持类型并允许其他文件类型；Info.plist `CFBundleDocumentTypes` 注册 Plain Text 与 Script/Source Code 两组文档类型；05 新增 IT-DOC-ED-007
- 打开 `.bat` 仍提示"打不开这种类型的文件"（第二轮修复）：本机系统将 `.bat` 判为动态 UTI（`dyn.ah62d4rv4ge80e2py`，conforms `public.data`）、`.ini` 判为 `com.microsoft.ini`（conforms `public.text`），均不命中 `public.data`/`public.item`/`public.content` 精确匹配；兜底条件放宽为"typeName 不受支持 且 扩展名在受支持清单内"即按纯文本打开（`.png` 等仍拒绝），探针覆盖动态 UTI 场景

### Changed
- 标签栏视觉改版为 macOS 原生风格（用户决策，替代 Win11 复刻规格；自绘架构与交互不变）：标签改为浮动圆角卡片（四边圆角 6pt、高 24pt、间距 2pt），选中用 `controlBackgroundColor`、未选中透明 hover 微显，相邻未选中标签间 1px 分隔线，关闭按钮移至左侧，未保存圆点与拖拽指示线改系统强调色 `controlAccentColor`；02_UI_DESIGN.md §5.1 同步修订
- 标签栏/状态栏颜色不随主题切换：动态系统色直接取 `.cgColor` 会按全局当前外观解析（切换瞬间解析成旧外观），改为 `resolvedColor(with: effectiveAppearance)` 按视图有效外观解析（NPTabBarView/NPTabItemView/NPStatusBarView/NPStatusBarButton）
- 视图菜单"下一个/上一个标签页"缺本地化（en 两项、中文各一项），菜单曾显示原始 key
- "格式→自动换行"无勾选状态：`validateMenuItem` 未加 `@objc` 未暴露给 ObjC 运行时，AppKit 动态校验找不到该方法（编译器 note 证实）；NPEditorView 与 AppDelegate 两处一并补上（后者影响状态栏/主题/置顶勾选的稳定性），探针验证勾选随偏好切换
- 查找栏改版对齐 Win11 样式：查找输入框左侧新增折叠/展开箭头（收起 ∧、展开 ∨），点击切换替换界面；替换输入框左缩进与查找框对齐；新增 FindBar.ToggleReplace 本地化（en/简中/繁中）
- 查找栏细化：替换输入框与查找输入框等宽；查找栏整体压箭头光标（此前透出下层文本视图的 I 形光标），输入框内仍显示 I 形光标
- 查找栏替换行错位：垂直 NSStackView 默认按内容居中排列两行，行内容宽度不同导致整行右偏；改为两行显式等宽撑满容器，替换行缩进占位改为跟随折叠箭头实际宽度，两输入框左缘/宽度探针实测完全对齐
- 查找栏光标恒为 I 形（二次修复）：addCursorRect 压不住下层 NSTextView 反复重挂的 I 形光标矩形；改为跟踪区域在 mouseEntered/mouseMoved 时强制箭头光标，命中输入框或字段编辑器（NSTextView）时放行保留 I 形
- 查找栏从悬浮遮挡改为推动布局（用户决策，根除光标/命中区域与下层文本视图重叠问题）：改为内容视图垂直 NSStackView 首个成员，隐藏时自动折叠、显示时把编辑区整体下推；NPFindBarController 不再做悬浮挂载，高度约束改为常驻；02_UI_DESIGN.md §5.2 同步修订
- 查找栏背景在浅色模式下与编辑区背景（#FFFFFF）难区分：原 `NSVisualEffectView` 毛玻璃（headerView 材质）改为 `NPColorPalette.findBarBackground` 纯色（浅色由 #F9F9F9 加深至 #F0F0F0，深色 #2B2B2B 不变），外观切换即时重解析；02_UI_DESIGN.md §5.2 同步修订
- 文件类型从白名单改为全接受（v1.4 架构决策）：不按扩展名/UTI 预筛选，任意文件均尝试打开，编码检测（NUL 字节 + 控制字符比例）在 `read(from:)` 中判定是否为纯文本，非文本内容以中文提示"此文件不是纯文本文件，无法打开。"（PNG 等二进制实测抛 `NPEncodingError.undetectable`）；`NPDocumentController` 大幅简化（`documentClass` 全返回 `NPTextDocument.self`，移除 `makeDocument` 兜底与 `isSupportedTextType`，`runModalOpenPanel` 全文件可选）；`NPConstants.TextTypes` 退役为文档参考；`NPEncodingError` 加 `LocalizedError` 协议四分支中文描述；Info.plist 新增 `public.item` 兜底文档类型；05 相关用例更新
- App 图标：接入用户提供的 AppIconSet 全套尺寸（16/32/64/128/256/512/1024），`iconutil` 生成 `AppIcon.icns` 入 Resources（源 PNG 为 AI 工具非标准编码，经 PIL 重写为 8-bit RGBA 后 iconutil 才可生成）；Info.plist 声明 `CFBundleIconFile=AppIcon`；dev-build.sh 增加 icns 拷贝；Assets.xcassets/AppIcon.appiconset 同步 10 个尺寸文件与 Contents.json（Xcode 构建路径可用）

### Added
- 崩溃监控（Phase 4，04 §5.5）：`NPCrashReporter`（Sentry，SPM 引入；DSN 经 Info.plist `SentryDSN` 注入，留空不启用；`beforeSend` 统一脱敏——主目录/临时目录/`file://` URL 替换为 `<redacted>`，日志不含文件路径与内容片段；未链接 Sentry SDK 时优雅降级为空操作）+ `NPCrashSanitizer`（纯函数，可独立单测）；AppDelegate 启动接线
- 自动更新（Phase 4，04 §5.2）：`NPUpdateService`（Sparkle 封装，`SPUStandardUpdaterController`；`checkForUpdates` / `isAutomaticCheckEnabled` / `lastCheckDate` 对齐契约；整文件 `#if !APP_STORE` 剔除，未链接 Sparkle 时降级为空操作）；菜单"检查更新…"接通
- 反馈渠道（Phase 4，06 §7.2）：`NPFeedbackComposer`（mailto 链接纯函数构造，主题/正文本地化、版本信息自动填充）+ 三语 `Feedback.MailSubject` / `Feedback.MailBody` 文案；帮助菜单"发送反馈…"接通
- macOS 服务菜单（PRD FR-021）：Info.plist `NSServices` 声明"用所选文字新建文档"服务 + `AppDelegate` 实现 `NSServicesMenuRequestor`（`nonisolated` + `MainActor.assumeIsolated` 显式主线程断言）；`NSApp.servicesProvider` 启动注册
- Info.plist 新增 `SentryDSN` / `SUFeedURL` / `SUPublicEDKey` 占位键（发布构建填写真实值；06 §3.2/§7.3 接入说明）
- 单元测试：UT-CRASH-001 ~ 004、UT-FEED-001 ~ 003（05 新增 §2.7/§2.8）

### Changed
- AppDelegate 清理过期 TODO：状态栏显隐已由状态栏模块消费（04 §3.1）；偏好设置窗口仍为未接线的占位（04 §4.1，后续迭代项）
- 备份缓存垃圾清理增强：`cleanExpiredBackups()` 退役，改为 `recoverableRecords()` 只返回有效记录（文件对完整、元数据可解码、未超 7 天保留期）+ 新增 `pruneInvalidBackupFiles(keeping:)` 删除目录中白名单外一切文件（原子写入 `*.sb-*` 临时残留、孤儿单边文件、损坏元数据、超期备份）；启动流程改为先加载有效记录再清掉其余；04 §5.3、05 UT-BACKUP-003 同步
- 自动保存写回在用户目录遗留 `未命名.txt.sb-*` 临时文件：`writeBackToOriginal` 的沙盒原子写（`Data.write(.atomic)`）跨容器边界的临时文件无法回收；改为非原子写（崩溃安全本就由会话备份承载），不再产生 `.sb-` 垃圾
