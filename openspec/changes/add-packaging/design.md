# Design

## Context

见 proposal.md。已经有 make-app-bundle.sh 和 Info.plist，但没有 dmg 脚本、README 和完整的依赖清单。

## Goals / Non-Goals

**Goals:**

- 一条命令出 dmg。
- 体积和签名状态可验证。
- 发布材料齐全。

**Non-Goals:**

- Developer ID 签名与公证（缺账号）。
- 第一屏 GIF（缺屏幕录制）。

## Decisions

### D1 开发 bundle 与发布 bundle 共用脚本

make-app-bundle.sh 组装 .app 并 ad-hoc 签名；make-dmg.sh 调它，再按 SIGN_IDENTITY 决定是否用正式证书重签。没有证书也能出包，只是 Gatekeeper 会拦。

### D2 版本从环境变量读

VERSION 默认 0.1.0，dmg 文件名带版本。正式发版时用语义化版本。

### D3 hdiutil UDZO

用 hdiutil create -format UDZO 压缩，挂载后是只读卷。

### D4 README 第一屏只放数字

一句话、三个实测数字、支持格式，不放架构图和功能长列表。

## Risks / Trade-offs

- [ad-hoc 包被 Gatekeeper 拦] → README 与脚本都明确说明，正式发布前补 Developer ID。
- [签名后 dmg 体积变化] → 27MB，离 30MB 上限还有余量。
- [Info.plist 的 Bundle ID 是占位] → 正式名前再定，见 R-DEC-06。

## Migration Plan

新增打包脚本，没有数据迁移。

## Open Questions

无。
