# 发版清单

## 发版前必须由人决定

- 产品英文名（GitHub 仓库名、包名）：暂用 TableWorkbench
- Bundle ID：dev.kongqi.tableworkbench，改域名时同步 Info.plist
- 开源许可证：Apache-2.0，LICENSE 与 NOTICE 已放入仓库
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

- 30 秒内 GIF：拖入 500MB CSV → 表格出现 → 滚到底 → 透视
- 三个数字：冷打开 2.0s、二次 0.59s、第 100 块 0.12s（发版前用最终包复测）
- 一句对比：Excel 打开要三分钟的文件，这里两秒
- 安装命令或 dmg 链接

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
