# Spec Delta

## Purpose

描述应用如何组装成 .app 和 dmg、如何签名，以及发布材料需要包含什么。

## ADDED Requirements

### Requirement: 组装 .app

应用 SHALL 能由脚本组装成 .app，包含 Info.plist、可执行文件和 Bundle ID，双击能启动。

#### Scenario: 启动组装后的应用
- **WHEN** 用户运行 make-app-bundle.sh 并打开产物
- **THEN** 应用启动，窗口出现

### Requirement: 生成 dmg

应用 SHALL 能生成 dmg，体积不超过 30MB，挂载后包含 .app。

#### Scenario: 挂载 dmg
- **WHEN** 用户双击 dmg
- **THEN** 看到 TableWorkbench.app，可拖入 Applications

### Requirement: 签名与公证

有 Developer ID 证书时，脚本 SHALL 用正式证书签名并支持公证；没有证书时 SHALL 退回 ad-hoc 并明确提示会被 Gatekeeper 拦截。

#### Scenario: 没有证书
- **WHEN** 未设置 SIGN_IDENTITY
- **THEN** 脚本输出警告，产物是 ad-hoc 签名

### Requirement: 发布材料

仓库 SHALL 包含 README 与第三方依赖清单。README 第一屏 SHALL 有一句话、实测数字和支持格式。

#### Scenario: 查看 README
- **WHEN** 用户打开 README
- **THEN** 第一屏能看到三个数字和一句定位
