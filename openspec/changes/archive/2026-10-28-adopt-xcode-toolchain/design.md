# Design

## 为什么产物必须在 iCloud 之外

仓库在 ~/Documents，iCloud 的 fileprovider 会给目录里新建的文件挂上 `com.apple.FinderInfo` 与 `com.apple.fileprovider.fpfs#P` 扩展属性。SwiftPM 在 macOS 上默认走 SwiftBuild 后端，构建时会为资源包（例如 ZIPFoundation 的 `.bundle`）做 ad-hoc 签名，而 `codesign` 见到这两个属性会直接拒绝：

    resource fork, Finder information, or similar detritus not allowed

换 `--build-system native` 后不再签资源包，签名错误消失，但实测两次（CLT 工具链一次、Xcode 工具链一次）都会在编译阶段跑完之后空转：进程 CPU 0%、llbuild 的 8 条 lane 全部停在 `__psynch_cvwait`，主线程在 run loop 里，半小时没有新产物。判断与 fileprovider 对构建目录的持续同步有关，没有进一步抓系统调用确认。

把 scratch 目录指到 `~/Library/Caches/tableworkbench-build` 之后，同一套 native 后端能编完 release，打出来的 .app 打开 `bench-data/wide-100k.csv` 显示 100000 行，功能正常。

## 为什么保留 native 后端

既然产物已经在 iCloud 之外，理论上可以试试默认的 SwiftBuild 后端（不弃用、长期更稳）。这次没试成功：每换一次后端都要把 DuckDB 的 C++ 全量重编一遍（十几分钟），先把可用路径固化下来，等下一次有空再试默认后端。风险是 `--build-system native` 已被标弃用，SwiftPM 将来删掉它就得把仓库搬出 iCloud。

## 否决的方案

- 只在失败的那一个 bundle 上 `xattr -c`：fileprovider 会重新打上，治标不住。
- 关掉整机 iCloud 同步：影响用户其它文件，超出这次任务范围。
- 把仓库搬到 ~/Developer：能根治，但会打断现有工作区路径与会话上下文，留作备选。
- 用 `xcodebuild` 取代 swift build：会引入 `.xcodeproj`，与"单 SPM 工程"的现状冲突，收益不明。

