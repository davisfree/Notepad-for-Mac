## 变更说明

<!-- 本次 PR 做了什么？关联的 Issue / PRD FR 编号 -->

## 变更类型

- [ ] 新功能
- [ ] Bug 修复
- [ ] 重构（功能等效）
- [ ] 文档 / 配置

## 自查清单（见 08_KIMI_INSTRUCTION.md 第 9 节）

- [ ] 代码符合 `03_DEV_GUIDE.md` 规范，SwiftLint 无警告
- [ ] public/internal 方法均有 `///` 文档注释
- [ ] 无强制解包 / 隐式解包可选类型
- [ ] 代理为 `weak`，闭包显式 `[weak self]`
- [ ] UI 操作均在主线程
- [ ] 用户可见字符串已本地化（`NSLocalizedString`）
- [ ] 未引入逆向模块依赖
- [ ] 已添加 / 更新单元测试，且全部通过
