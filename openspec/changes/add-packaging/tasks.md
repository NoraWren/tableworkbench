# Tasks

## 1. 组装

- [x] 1.1 Info.plist 包含 Bundle ID、版本、文档类型，验证 plutil 通过
- [x] 1.2 make-app-bundle.sh 组装 .app 并 ad-hoc 签名，验证能启动
- [x] 1.3 make-dmg.sh 生成 dmg，验证挂载后包含 .app
- [x] 1.4 检查 dmg 体积，验证不超过 30MB

## 2. 发布材料

- [x] 2.1 写 README 第一版，验证第一屏有定位、三个数字、支持格式
- [x] 2.2 更新第三方依赖清单，验证版本与许可证准确

## 3. 待补

- [ ] 3.1 Developer ID 签名与公证（缺账号）
- [ ] 3.2 第一屏 GIF 与发布渠道（缺录屏与发布窗口）
