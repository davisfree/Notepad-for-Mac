# Notepad for macOS — 发布与部署规范 (RELEASE)

> **版本**：v1.1  
> **日期**：2026-08-02  
> **适用范围**：内测、公测、App Store、官网直发、Homebrew  
> **v1.1 修订**：Homebrew 渠道改为现代 Cask 格式（分发 .zip，与 01_TECH_SPEC §6.3 对齐）；新增 App Store 构建约束（`#if !APP_STORE` 整体剔除 Sparkle/NPUpdateService）；修正签名与公证流程（钥匙串凭证、逐层签名、DMG 纳入主流程、双端装订）；新增 Sparkle EdDSA 密钥管理；回滚策略、隐私政策、版本号字段与检查清单对齐已定案决策

---

## 1. 版本号规范（Semantic Versioning）

```
主版本号.次版本号.修订号-预发布标识
例如：1.0.0, 1.1.0-beta.2, 1.0.1-hotfix.1
```

| 位置       | 递增规则                                      |
| ---------- | --------------------------------------------- |
| 主版本号   | 重大架构变更、不兼容的 API 修改               |
| 次版本号   | 新功能发布、向下兼容的扩展                    |
| 修订号     | Bug 修复、性能优化、安全补丁                  |
| 预发布标识 | alpha（内测）→ beta（公测）→ rc（候选）→ 正式 |

**Info.plist 双版本字段**：

- `CFBundleShortVersionString`（对外展示）：遵循上述 SemVer，如 `1.0.1`
- `CFBundleVersion`（构建号）：每次构建单调递增的整数（含热修复），如 `43`
- Sparkle 以 appcast 中的 `sparkle:version`（对应 `CFBundleVersion` 构建号）比较更新；若热修复只改 `CFBundleShortVersionString` 而构建号不变，已安装用户会被误判"已是最新"，收不到修复

---

## 2. 发布流程

### 2.1 发布前检查清单

```
□ 所有 PR 已合并到 main 分支
□ 版本号已更新（Info.plist + 代码中的版本常量）
□ CHANGELOG.md 已更新
□ 单元测试覆盖率 ≥ 80%
□ CI 全部绿灯（GitHub Actions）
□ 手动回归测试通过（05_TEST_PLAN.md 清单）
□ 无 P0/P1 未修复 Bug
□ 本地化字符串已审核（中/英/繁）
□ App Icon 所有尺寸已导出
□ 隐私政策页面已上线
□ 截图/宣传素材已准备（App Store 需要）
□ Universal Binary 双架构构建并冒烟通过（`lipo -archs` 验证含 arm64 + x86_64）
□ 性能指标回归通过：冷启动 <500ms（Apple Silicon）/ <800ms（Intel）、热启动 <200ms、10MB 文件打开 <3s、空文档内存 <50MB、10 标签 <150MB
□ 包体积验收：核心 <5MB、完整直发版 <15MB
□ macOS 12（最低支持版本）真机或虚拟机回归通过
□ Hardened Runtime 已启用
□ security-scoped bookmark entitlement（`com.apple.security.files.bookmarks.app-scope`）已配置（沙盒下最近文件/会话恢复依赖）
□ App Store 构建已通过 `#if !APP_STORE` 整体剔除 Sparkle/NPUpdateService（产物无 Sparkle 符号、菜单无"检查更新"项；Apple 禁止应用内自更新）
```

### 2.2 构建流程

**构建配置差异（两渠道）**：

| 渠道                  | 编译标志 / 配置                                                     | ExportOptions `method`  | 更新方式          |
| --------------------- | ------------------------------------------------------------------- | ----------------------- | ----------------- |
| App Store             | 定义 `APP_STORE`，`#if !APP_STORE` 剔除 Sparkle/NPUpdateService；严格沙盒 | `app-store-connect`     | App Store 自动更新 |
| 官网直发 / Homebrew   | 不定义 `APP_STORE`（包含 Sparkle）                                  | `developer-id`（见 `Scripts/ExportOptions.plist`） | Sparkle 自动更新 |

> 以下流程以直发/Homebrew 构建为例；App Store 构建归档（步骤 4）后直接上传 App Store Connect，无需步骤 9-11 的 DMG 与公证。

```bash
# 0. 首次配置：将公证凭证存入钥匙串（避免命令行明文密码）
xcrun notarytool store-credentials "Notepad-Notarize" \
  --apple-id "developer@example.com" \
  --team-id "XXXXXXXXXX" \
  --password "<app-specific-password>"

# 1. 切换到发布分支
git checkout main
git pull origin main

# 2. 打版本标签
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0

# 3. 清理构建
xcodebuild clean -scheme Notepad

# 4. 归档（Release 配置，Universal Binary）
xcodebuild archive \
  -scheme Notepad \
  -configuration Release \
  -archivePath "build/Notepad.xcarchive"

# 5. 导出 Notepad.app
xcodebuild -exportArchive \
  -archivePath "build/Notepad.xcarchive" \
  -exportPath "build/Export" \
  -exportOptionsPlist "Scripts/ExportOptions.plist"

# 6. 逐层签名（由内向外；Apple 不推荐 codesign --deep）
#    先签 Sparkle.framework 内嵌 XPC/Helper，再签 Sparkle.framework，最后签主 app
SIGN_ID="Developer ID Application: Your Company (XXXXXXXXXX)"
codesign --force --options runtime --sign "$SIGN_ID" \
  "build/Export/Notepad.app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
codesign --force --options runtime --sign "$SIGN_ID" \
  "build/Export/Notepad.app/Contents/Frameworks/Sparkle.framework"
codesign --force --options runtime --sign "$SIGN_ID" \
  "build/Export/Notepad.app"

# 7. 签名验证
codesign --verify --verbose=4 "build/Export/Notepad.app"
spctl -a -vv "build/Export/Notepad.app"

# 8. 上传 dSYM 至 Sentry（否则线上崩溃堆栈无法符号化，§7 监控依赖）
sentry-cli upload-dif "build/Notepad.xcarchive/dSYMs"

# 9. 制作 DMG（统一命名 Notepad-{version}.dmg，详见 §2.3 渠道 B）
hdiutil create -srcfolder "build/Export/Notepad.app" \
  -volname "Notepad" -format UDZO -o "build/Export/Notepad-1.0.0.dmg"

# 10. 公证（提交 DMG，使用钥匙串凭证）
xcrun notarytool submit "build/Export/Notepad-1.0.0.dmg" \
  --keychain-profile "Notepad-Notarize" --wait

# 11. 装订票据（app 与 DMG 都装订）并验证
xcrun stapler staple "build/Export/Notepad.app"
xcrun stapler staple "build/Export/Notepad-1.0.0.dmg"
xcrun stapler validate "build/Export/Notepad-1.0.0.dmg"
```

### 2.3 分发渠道

#### 渠道 A：App Store

| 项目 | 要求                                   |
| ---- | -------------------------------------- |
| 沙盒 | 必须启用 App Sandbox                   |
| 权限 | 仅申请 `user-selected-file-read/write` |
| 签名 | Apple Distribution 证书                |
| 审核 | 需通过 Apple 人工审核（1-3 天）        |
| 更新 | App Store 自动更新                     |
| 收益 | 可设置付费/订阅（抽成 15%-30%）        |

**App Store 元数据**：

```
应用名称：Notepad - 纯文本编辑器
副标题：Windows 风格的 macOS 记事本
关键词：notepad, text editor, txt, 记事本, 文本编辑, windows
类别：Productivity / Utilities
年龄分级：4+
价格：免费（或 $4.99 一次性付费）
```

#### 渠道 B：官网直发（DMG）

| 项目 | 要求                                   |
| ---- | -------------------------------------- |
| 沙盒 | 可选（建议关闭以获得更好文件访问体验） |
| 签名 | Developer ID 证书                      |
| 公证 | 必须（macOS 10.15+ 要求）              |
| 更新 | Sparkle 框架自动更新                   |
| 分发 | 官网下载 + GitHub Releases             |

**DMG 制作规范**（脚本化，已集成于 `Scripts/release.sh`，禁止 Finder 手动操作）：

```bash
# 方式一：hdiutil 直接打包（简单场景）
hdiutil create -srcfolder "build/Export/Notepad.app" \
  -volname "Notepad" -format UDZO -o "Notepad-1.0.0.dmg"

# 方式二：create-dmg（定制背景图、图标布局、Applications 快捷方式）
create-dmg \
  --volname "Notepad" \
  --background "dmg-background.png" \
  --window-size 640 480 --icon-size 80 \
  --icon "Notepad.app" 160 200 \
  --app-drop-link 480 200 \
  "Notepad-1.0.0.dmg" \
  "build/Export/Notepad.app"
```

> 产物统一命名为 `Notepad-{version}.dmg`，与 §2.2 主流程步骤 9 一致；DMG 需随主流程一并公证并装订票据。

#### 渠道 C：Homebrew

```ruby
# Casks/notepad.rb（提交至官方 homebrew-cask 或自建 tap）
cask "notepad" do
  version "1.0.0"
  sha256 "..."

  url "https://github.com/yourcompany/notepad-mac/releases/download/v1.0.0/Notepad-1.0.0.zip"
  name "Notepad"
  desc "Windows-style text editor for macOS"
  homepage "https://github.com/yourcompany/notepad-mac"

  app "Notepad.app"
end
```

> 分发物为 `.zip`（brew cask 分发 zip，与 01_TECH_SPEC §6.3 对齐）。签名+公证要求与官网直发相同（Gatekeeper 与官方 cask 仓库均要求公证后的产物）。

---

## 3. 更新策略

### 3.1 自动更新（Sparkle）

```xml
<!-- appcast.xml -->
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Notepad Changelog</title>
    <item>
      <title>Version 1.0.1</title>
      <pubDate>Tue, 15 Sep 2026 10:00:00 +0800</pubDate>
      <enclosure url="https://example.com/Notepad-1.0.1.dmg"
                 sparkle:version="43"
                 sparkle:shortVersionString="1.0.1"
                 length="5242880"
                 type="application/octet-stream"
                 sparkle:edSignature="xxxxxxxxxxxxxxxx"/>
      <description><![CDATA[
        <h2>Bug Fixes</h2>
        <ul>
          <li>Fixed encoding detection for GB18030 files</li>
          <li>Improved auto-save reliability</li>
        </ul>
      ]]></description>
    </item>
  </channel>
</rss>
```

### 3.2 Sparkle EdDSA 密钥管理

```bash
# 1. 生成密钥对（仅一次，工具随 Sparkle 分发）
./bin/generate_keys

# 2. 公钥写入 Info.plist
#    SUPublicEDKey = <base64 公钥>

# 3. 每次发布对更新包签名（输出 sparkle:edSignature 与文件长度，写入 appcast）
./bin/sign_update "Notepad-1.0.1.dmg"
```

- 私钥仅保存于本地钥匙串/离线介质，**禁止提交 Git**（呼应 07_PROJECT_STRUCTURE §8.2）
- 私钥泄露时需重新生成密钥对，并随下一版本轮换 `SUPublicEDKey`

### 3.3 更新频率

| 类型     | 频率      | 内容               |
| -------- | --------- | ------------------ |
| 热修复   | 随时      | P0 崩溃修复        |
| 功能更新 | 每 2-4 周 | 新功能 + Bug 修复  |
| 大版本   | 每 3-6 月 | 架构升级、重大功能 |

### 3.4 Sparkle SDK 接入（SPM）

代码层已按 `#if canImport(Sparkle)` + `#if !APP_STORE` 接好（`Services/NPUpdateService.swift`），链接 SDK 后即生效；开发构建（swiftc 直编，无 Sparkle）自动降级为空操作。

```yaml
# project.yml 增加包依赖（xcodegen 生成工程后生效）
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: 2.5.0
targets:
  Notepad:
    dependencies:
      - package: Sparkle
        product: Sparkle
```

- 需在 Info.plist 填写 `SUFeedURL`（appcast 地址）与 `SUPublicEDKey`（§3.2 生成的 EdDSA 公钥）
- **App Store 构建禁止链接 Sparkle**（Apple 禁止应用内自更新）：构建配置注入 `APP_STORE` 编译标志后，`#if !APP_STORE` 整体剔除本模块（§2.2 表格）

---

## 4. 发布文档模板

### 4.1 CHANGELOG.md

```markdown
# Changelog

## [1.0.1] - 2026-09-15

### Fixed
- 修复 GB18030 编码检测在特定字符组合下的误判问题 (#45)
- 修复自动保存在文件名包含特殊字符时失败的问题 (#42)
- 修复深色模式下状态栏文字对比度不足的问题 (#38)

### Improved
- 优化 10MB 以上文件的打开速度（提升 30%）
- 减少内存占用约 15%

## [1.0.0] - 2026-08-20

### Added
- 初始版本发布
- 完整复刻 Windows 11 Notepad 功能
- 支持多标签页、多编码、多换行符格式
- 浅色/深色主题，跟随系统
- 自动保存与会话恢复
```

### 4.2 Release Notes（用户可见）

```
Notepad 1.0.1 更新内容：

🐛 修复：
• GB18030 编码文件打开更准确
• 自动保存更稳定可靠
• 深色模式状态栏显示优化

⚡ 优化：
• 大文件打开速度提升 30%
• 内存占用降低 15%

感谢所有用户的反馈！
```

---

## 5. 回滚策略

| 场景               | 回滚方案                                                     |
| ------------------ | ------------------------------------------------------------ |
| 严重 Bug 发现      | 立即下架当前版本，恢复上一版本下载链接                       |
| App Store 审核被拒 | 修复问题后重新提交，保留当前版本在线                         |
| 公证失败           | 修复签名/权限问题，重新公证并更新下载链接                    |
| 更新导致崩溃       | 从 appcast 移除问题 `<item>`，使新检查的用户不再收到该更新；同时尽快发布修复版覆盖已安装用户。注意 Sparkle 无远程封禁已安装版本的能力（`sparkle:minimumSystemVersion` 语义为"更新所需的最低系统版本"，不能用于回滚） |

---

## 6. 隐私与合规

### 6.1 隐私政策要点

```
Notepad 隐私政策

1. 数据收集：本应用不收集任何用户文件内容、个人信息。
2. 会话备份：仅存储于本应用本地数据目录（沙盒容器内），不上传云端。
3. 崩溃日志：可选上传匿名化崩溃信息，不含文件路径与内容。
4. 第三方服务：仅使用 Sparkle（更新检查）和 Sentry（崩溃监控）。
5. 权限：仅申请用户选择的文件读写权限，不访问其他文件。
6. 更新检查：Sparkle 检查更新时会向更新服务器发送 macOS 系统版本等基本设备信息。
```

### 6.2 App Store 审核准备

| 审核项   | 准备内容                                                     |
| -------- | ------------------------------------------------------------ |
| 屏幕截图 | 5 张（浅色/深色各 2 张 + 1 张特色图），1280×800 或 2880×1800 |
| 预览视频 | 可选，15-30 秒，展示核心功能                                 |
| 演示账号 | 无需                                                         |
| 权限说明 | 仅当声明了 Documents 目录访问 entitlement 时才需提供 `NSDocumentsFolderUsageDescription`；经 NSOpenPanel/拖拽的用户选择文件访问（powerbox）不需要任何 usage description |
| 年龄分级 | 4+，无暴力/成人内容                                          |

---

## 7. 发布后监控

### 7.1 关键指标

| 指标             | 健康阈值              | 监控工具                     |
| ---------------- | --------------------- | ---------------------------- |
| 日活用户（DAU）  | > 1000（发布后 1 月） | App Store Connect / 自建统计 |
| 崩溃率           | < 0.1%                | Sentry / Xcode Organizer     |
| 平均评分         | ≥ 4.5                 | App Store Connect            |
| 更新 adoption 率 | > 80%（发布后 1 周）  | Sparkle / App Store          |
| 启动成功率       | > 99.9%               | Sentry                       |

### 7.2 用户反馈渠道

- App Store 评论（每日查看）
- 应用内"发送反馈"（邮件或 GitHub Issue）
- 社交媒体 / 论坛监控
- 崩溃报告自动分类（Sentry）

### 7.3 崩溃监控接入（Sentry，SPM）

代码层已按 `#if canImport(Sentry)` 接好（`Services/Analytics/NPCrashReporter.swift`），链接 SDK 后即生效；开发构建（swiftc 直编，无 Sentry）自动降级为空操作。

```yaml
# project.yml 增加包依赖（xcodegen 生成工程后生效）
packages:
  Sentry:
    url: https://github.com/getsentry/sentry-cocoa
    from: 8.20.0
targets:
  Notepad:
    dependencies:
      - package: Sentry
        product: Sentry
```

- 需在 Info.plist 填写 `SentryDSN`（留空则不启用监控）；`beforeSend` 已统一脱敏（主目录/临时目录/`file://` URL 替换为 `<redacted>`，01 §5 隐私约束）
- 发布时执行 §2.2 步骤 8 上传 dSYM，线上崩溃栈方可符号化
- **App Store 构建允许 Sentry**（无自更新违规项）；仅 Sparkle 必须剔除（§3.4）

---

## 8. 灾难恢复

```
场景：生产版本出现严重 Bug，需要紧急修复

T+0min   发现严重 Bug，评估影响范围
T+5min   在 main 分支创建 hotfix/v1.0.1 分支
T+30min  修复 Bug，本地验证
T+45min  跑完全部回归测试
T+60min  合并到 main，打标签 v1.0.1
T+90min  构建 + 签名 + 公证完成
T+2h     官网更新 DMG，Sparkle appcast 更新
T+2h     App Store 提交紧急审核（如适用）
T+24h    App Store 审核通过（紧急通道）
```