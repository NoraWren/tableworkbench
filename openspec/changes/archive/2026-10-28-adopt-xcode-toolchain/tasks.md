# Tasks

## 1. 构建链路

- [x] 1.1 确认 Xcode 27.1 装好、许可通过、`xcodebuild -version` 有输出
- [x] 1.2 复现并定位签名失败（SwiftBuild 签资源包撞 fileprovider 扩展属性）
- [x] 1.3 复现并定位 native 后端空转（llbuild lane 全部 __psynch_cvwait）
- [x] 1.4 scratch 目录外置后 release 全量编过，产出 55 MB 可执行文件
- [x] 1.5 make-app-bundle.sh 用外置 scratch 打出 .app，启动后打开 wide-100k.csv 显示 100000 行
- [x] 1.6 其余 6 个 build/bench 脚本统一加 `--build-system native --scratch-path "$scratch"`，`TW_BUILD_DIR` 可覆盖，bash -n 全过
- [x] 1.7 清掉仓库里的 app/.build

## 2. 能力确认

- [x] 2.1 `@State`/`@Bindable` 探针编译通过（此前只有 @Observable 能过）
- [x] 2.2 `#Preview` 探针编译通过
- [x] 2.3 XCTest.framework 与 Testing.framework 存在于 Xcode 平台目录
- [x] 2.4 Instruments.app 在位
- [x] 2.5 用 Xcode 工具链跑 `swift run TableWorkbenchTests`，全部通过

## 3. 文档

- [x] 3.1 AGENTS.md 环境表与"容易踩的坑"更新
- [x] 3.2 12-decisions-risks.md 记 R-DEC-21
- [x] 3.3 11-milestones.md R-MS-01 勾掉 Xcode 与 SPM 两条
- [x] 3.4 openspec validate --strict adopt-xcode-toolchain 通过

