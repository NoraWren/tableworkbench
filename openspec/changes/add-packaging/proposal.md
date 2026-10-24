# Proposal

## Why

功能做完了没有 dmg，等于没发布。R-REL-01 到 R-REL-03 要求能打出一个可下载的包，README 第一屏能讲清三个数字。

## What Changes

- 开发用 .app 组装脚本：SPM 产物 + Info.plist + ad-hoc 签名。
- dmg 打包脚本：构建、签名（有证书时用 Developer ID）、hdiutil 生成 UDZO。
- README 第一版：一句话、三个数字、支持与不支持、构建方式、已知限制。
- 第三方依赖清单：DuckDB、CoreXLSX、ZIPFoundation、XMLCoder 的版本与许可证。

## Capabilities

### New Capabilities

- packaging：应用组装、dmg、README 与依赖披露。

### Modified Capabilities

无。openspec/specs 尚未归档。

## Impact

- 新增 scripts/make-dmg.sh，更新 make-app-bundle.sh 的用法。
- 新增 README.md。
- 更新 docs/third-party.md。

## 不做什么

- 没有 Apple Developer 账号前不做 Developer ID 签名和公证。
- 不录第一屏 GIF（屏幕锁着，无法录屏）。
- 不做自动更新和 Homebrew Cask。

## 性能与只读

dmg 目标不超过 30MB。安装包不联网，不含任何遥测。
