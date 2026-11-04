# Tasks

## 1. 组装

- [x] 1.1 Info.plist 包含 Bundle ID、版本、文档类型，验证 plutil 通过
- [x] 1.2 make-app-bundle.sh 组装 .app 并 ad-hoc 签名，验证能启动
- [x] 1.3 make-dmg.sh 生成 dmg，验证挂载后包含 .app
- [x] 1.4 检查 dmg 体积，验证不超过 30MB

## 2. 发布材料

- [x] 2.1 写 README 第一版，验证第一屏有定位、三个数字、支持格式
- [x] 2.2 更新第三方依赖清单，验证版本与许可证准确
- [x] 2.3 开源许可证落地：LICENSE 与 NOTICE 随应用包分发，关于页与 Info.plist 写明 Apache-2.0，逐个核对四个依赖的 LICENSE 文件，验证构建通过

## 3. 待补

- [ ] 3.1 Developer ID 签名与公证（缺账号）
- [ ] 3.2 第一屏 GIF 与发布渠道（GIF 已于 2026-10-28 重录，拖入动作进前 3 秒；仍缺发布渠道与发布窗口）
