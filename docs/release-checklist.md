# 发版清单

## 发版前必须由人决定

- 产品英文名（GitHub 仓库名、包名）：暂用 TableWorkbench
- Bundle ID：dev.kongqi.tableworkbench，改域名时同步 Info.plist
- 开源许可证：Apache-2.0。LICENSE 与 NOTICE 在仓库根目录，make-app-bundle.sh 会把两份一起放进 app 的 Resources；关于页与 Info.plist 都已写明
- 著作权归属与对外发布审批：仍需确认

## 签名与公证

需要 Apple Developer Program 账号和 Developer ID Application 证书。

    export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
    ./scripts/make-dmg.sh

公证：

    xcrun notarytool submit build/TableWorkbench-0.1.0.dmg \
      --keychain-profile "notary-profile" --wait
    xcrun stapler staple build/TableWorkbench-0.1.0.dmg
    spctl --assess --type open --context context:primary-signature build/TableWorkbench-0.1.0.dmg

验收：在一台没装过 Xcode 的 Mac 上双击 dmg，能直接打开。

## 第一屏材料

- GIF 已用 release 包重录（2026-10-28）：从访达拖入 500mb.csv → 3,266,000 行出表 → 滚动表格 → 一键分析出 5 张图，820×474、7.1 秒 89 帧、440 KB。前 3 秒就是拖入动作。重录用 `./scripts/record-demo.sh`，给窗口坐标和秒数即可。
- 拖入动作最早录不进去，原因是 SwiftUI 的 dropDestination 挂在了分栏视图的兄弟层，AppKit 沿父链找不到接收器，不是录屏的问题。2026-10-27 改成窗口内容视图接收（见 R-IMP-08 与 openspec/changes/fix-window-file-drop），离屏、回调、真机访达拖拽都验过，截图见 docs/media/verification/drop-real-*.png。
- 三个数字（2026-10-27 复核，release）：冷打开中位 1.546 秒、二次 0.02–0.06 秒、第 100 块 0.06 秒；滚动每帧 1.0 毫秒；冷启动中位 0.497 秒（`./scripts/bench-launch.py --rounds 20` 跑八批共 152 轮，p95 0.537 秒，超预算 0/152）
- 一句对比：Excel 打开要等很久的文件，这里一点几秒（Excel 侧还没实测，发布前补一次，补不上就不写）
- 安装命令或 dmg 链接（还没有公开 release）

## 发布渠道

Hacker News（Show HN）、Reddit（r/dataisbeautiful、r/programming、r/macapps）、X、V2EX、即刻、少数派。

每个渠道单独写标题和正文，不复制粘贴同一段。

## 发布后 48 小时

- 回复所有 issue 和评论
- 记录崩溃和安装失败的反馈
- 把复现步骤转成任务

## 已知缺口

- AI 分析是 v0.2，不在首发范围
- 取消长查询依赖 duckdb-swift 暴露 interrupt
- 导出暂无进度条和取消
