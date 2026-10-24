# 10 打包与发布

这一章决定项目能不能被人看到。代码写完了没发出去，等于没做。

## R-REL-01 构建与签名

- 优先级：P0
- 状态：已定义
- 行为：
  - 用 Developer ID Application 证书签名，开启 Hardened Runtime。
  - 需要 Apple Developer Program 账号，99 美元一年，属前置条件，不是可选项。
  - 打包成 dmg，内含拖拽到 Applications 的引导。
- 验收：
  - [ ] codesign --verify --deep --strict 通过
  - [ ] spctl --assess 显示 accepted
  - [ ] 在一台没装过 Xcode 的 Mac 上双击能直接打开，不出现"无法验证开发者"
- 边界：不上 App Store，不申请沙盒。
- 依赖：R-DEC-04

## R-REL-02 公证

- 优先级：P0
- 状态：已定义
- 行为：用 notarytool 提交公证，成功后 staple 到 dmg。
- 验收：
  - [ ] notarytool 返回 Accepted
  - [ ] xcrun stapler validate 通过
  - [ ] 断网状态下首次打开仍然不触发 Gatekeeper 拦截
- 边界：不做自动发布流水线，先手动跑通。
- 依赖：R-REL-01

## R-REL-03 README 与演示

- 优先级：P0
- 状态：已定义
- 行为：README 结构固定。
  1. 一张 GIF，8 秒内，拖入到出数据。
  2. 一句话定位加一句对比。
  3. 三个数字：打开速度、包体积、冷启动，注明测试机型。
  4. 下载链接和安装命令。
  5. 支持的格式和已知限制，诚实列出。
  6. 一节"为什么不用 Excel"，三句话以内。
  7. 开发说明、许可证、贡献方式。
- 验收：
  - [x] GIF 不超过 8 MB，GitHub 上能直接播（docs/media/demo.gif，947 KB，8 秒）
  - [ ] 第一屏（不解屏）就能看到 GIF 和三个数字
  - [ ] 已知限制一节里至少写了三条真实限制
- 边界：不写路线图和愿景。
- 依赖：R-SCOPE-05

## R-REL-04 发布渠道

- 优先级：P0
- 状态：已定义
- 行为：首发同时投这些地方，顺序按转化率。
  1. Hacker News 的 Show HN，英文标题。
  2. Reddit：r/dataisbeautiful、r/programming、r/macapps。
  3. X，配 GIF，英文。
  4. V2EX 分享创造，中文。
  5. 即刻、少数派，中文。
  6. GitHub Trending 靠前两天 star 撬动，不额外操作。
- 验收：
  - [ ] 每个渠道的标题和正文都单独写过，不是同一段复制
  - [ ] 发布后 48 小时内回复所有 issue 和评论
- 边界：不买推广，不刷 star。
- 依赖：R-REL-03

## R-REL-05 开源与合规

- 优先级：P0
- 状态：已定义
- 行为：
  - 许可证待定，见 R-DEC-07。
  - 引入的第三方依赖逐条列在 docs/third-party.md，写清名称、版本、许可证、用途。
  - README 里不出现任何从其他项目搬来的文案、截图、示例数据。
  - 公司代码一行都不搬进来，业务口径也不搬。
- 验收：
  - [ ] 每个依赖的许可证都是 MIT、Apache-2.0 或 BSD 之一
  - [ ] docs/third-party.md 的条目与 Package.resolved 一致
  - [ ] 仓库历史里没有公司内部代码的痕迹
- 边界：不做 CLA 流程，v0.1 用 DCO 签名即可。
- 依赖：R-DEC-07

## R-REL-06 版本与更新

- 优先级：P2
- 状态：已定义
- 行为：用语义化版本，0.x 阶段每个版本在 GitHub Releases 写清改了什么。v0.1 不内置自动更新，只在"关于"里放一个检查新版本的链接。
- 验收：
  - [ ] Releases 页面有 v0.1.0 的 dmg 和一句说明
  - [ ] 版本号在关于窗口里可见
- 边界：不接 Sparkle 之类的更新框架，v0.2 再说。
- 依赖：R-REL-01
