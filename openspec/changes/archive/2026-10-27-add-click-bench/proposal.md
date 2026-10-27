## 对应需求

- R-PERF-03：滚动与交互。第三条验收「点击一行到选中态出现不超过 50 毫秒」至今没有测量手段。
- R-PERF-07：基准记录。数字要能重复跑，才配写进 bench-history。

## Why

R-PERF-03 的前两条（垂直滚动、横向滚动）都有 scripts/bench-scroll.sh 量，
第三条一直空着，不是因为它达标了，是因为没有工具量。没有 Xcode 就没有
Instruments，而点击这件事又不能靠滚动基准代替：滚动量的是换偏移后的一次布局
与绘制，点击多了事件分发、命中测试、NSTableView 的选中改写、以及受影响行的
重绘这几步。

现在补，是因为这条验收是 P0 里最后一个没有证据的项，留着它整个条目就没法收口。

## What Changes

- 新增 `TableWorkbenchClickBench` 可执行程序：在最小 .app 的真实窗口里把网格建出来，
  依次往每一行真发一次鼠标按下与抬起，量「按下到选中态重绘完」的耗时。
- 选中必须真的发生，程序会核对每一击后该行确实进了选中集，没进就报数并以
  非零码退出，避免「量出一个漂亮数字但根本没选中」。
- `scripts/make-clickbench-bundle.sh`：把基准程序装进一个最小 .app。
  不带 bundle 的进程激活不了，窗口永远不是 key window，NSWindow 会把点击当成
  「激活应用」吞掉，量到的根本不是用户点击的那条路径。
- `scripts/bench-click.sh`：跑两份数据（500mb.csv、wide-100k.csv），把结果打到终端，
  并给出是否落在 50 ms 预算内的判定。
- 在 08-performance.md 勾掉那条验收并记下实测，在 bench-history.md 补一节。

## Capabilities

### New Capabilities

- `click-bench`：点击选中延迟的测量契约——点的是什么、量到哪一步为止、怎么证明选中真的发生了。

### Modified Capabilities

无。

## Impact

- `app/Package.swift`：新增 `TableWorkbenchClickBench` executable target。
- `app/Sources/TableWorkbenchClickBench/main.swift`：新增。
- `scripts/make-clickbench-bundle.sh`、`scripts/bench-click.sh`：新增。
- `docs/requirements/08-performance.md`、`docs/bench-history.md`：验收与实测记录。

## 性能与只读

只读，不碰数据库写入。程序读一份基准文件，建一个真实窗口，发点击事件，退出。

## 不做什么

- 不用 CGEvent 往屏幕坐标打真实点击。那样会被鼠标位置、屏幕缩放、有没有别的窗口挡住带偏，
  也没法无人值守跑。
- 不量双击、不量拖选、不量键盘移动选中。这一条验收说的是「点击一行」。
- 不引入自动化测试框架。
