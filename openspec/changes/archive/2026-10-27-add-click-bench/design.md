# Design

## 背景

R-PERF-03 第三条要求「点击一行到选中态出现不超过 50 毫秒」，但本机没有 Xcode，也就没有 Instruments。滚动基准量的是换偏移后的一次布局与绘制，点击多出来的几步（事件分发、命中测试、NSTableView 选中改写、受影响行重绘）它量不到，不能顶替。所以这一节的实质工作是：先把「怎么量」定死，再量。

## 1. 为什么不用 CGEvent 打真实点击

`CGEvent.post(tap: .cghidEventTap)` 打的是屏幕坐标，看起来最像真人。四条理由否掉它：

| 问题 | 后果 |
|---|---|
| 依赖鼠标当前所在屏幕、屏幕缩放、有没有别的窗口挡住 | 换台机器数字就变，不能进 CI |
| 要抢焦点，跑的时候人不能用电脑 | 无人值守做不到 |
| 系统合成与垂直同步混在中间 | 量到的不是应用侧耗时，超预算了也不知道怪谁 |
| 需要辅助功能权限 | 新机器上第一次跑会卡在授权弹窗 |

改成在进程内构造 `NSEvent.mouseEvent`，再投给 `NSTableView.mouseDown`。走的是和真实点击同一段处理代码，只是不经过窗口服务器。

## 2. NSTableView 的 mouseDown 会进事件跟踪循环

这是本轮踩得最狠的坑：直接 `table.mouseDown(down)` 或 `NSApp.sendEvent(down)`，程序会挂死。原因是 `NSTableView` 处理按下后会进事件跟踪循环，阻塞等 `mouseUp`，而离屏窗口里没人会发抬起。第一次跑挂了 67 分钟，最后 `kill -9`。

解法是先 `NSApp.postEvent(up, atStart: false)` 把抬起事件排进队列，再发按下。跟踪循环一启动就能从队列里取到抬起，正常走完选中路径。

## 3. 裸进程激活不了，必须装成 .app

命令行可执行文件里 `setActivationPolicy(.regular)` + `finishLaunching()` + `activate` + `NSRunningApplication.current.activate` 轮询 6 秒，`NSApp.isActive` 和 `window.isKeyWindow` 仍然都是 false。此时发进去的点击会被当成「激活应用」吞掉，`table.selectedRowIndexes` 一直是空的。

第一版没意识到这点，跑出来「均值 0.5 ms、选中没生效 3/3」。数字漂亮且明显不可能，`missed` 计数就是为这种情况准备的：选中不生效必须报错退出，不许把它当成绩。

所以有 `scripts/make-clickbench-bundle.sh`：复制可执行文件进 `build/ClickBench.app`，手写最小 Info.plist，ad-hoc 签名。开发期的 `make-app-bundle.sh` 解决的是同一个问题（macOS 14 之后未打包进程无法可靠激活）。

## 3.5 为什么不走 NSWindow.sendEvent

最初是用 `window.sendEvent(down)`，配上 `NSApp.postEvent(up)`，语义上最贴近真实点击。问题是 `NSWindow.sendEvent` 开头有一道检查：窗口不是 key window 时，这一击被当作「激活窗口」，不转给内容视图。

这在测量机上会随机爆掉。程序跑到第 31 击时，系统把应用压到后台（`NSApp.isActive` 变 false），接下来每一击都只被当成激活，`selectedRowIndexes` 一直是空的。加 IO 断言禁止显示器休眠、把窗口提到浮动层、每击前重抢焦点，都只能减少频率，消不掉。有一轮 40 击里 22 击作废。

改成直接 `table.mouseDown(with: down)`：绕开那道检查，命中、选中、重绘照常走，抬起事件照样由排队的 `NSApp.postEvent(up)` 提供给内部跟踪循环。之后同一台机器连跑六轮、每轮 40–60 击，未选中一直是 0。

代价是起点比「用户按下」晚一步，不含窗口服务器把事件送到应用这一段。这一段是系统输入延迟，不随网格实现变化，本来也不该算进「点击到选中态」。

### 另一条被否掉的路：自己驱动事件泵

试过自己写 `NSApp.nextEvent(...)` + `sendEvent` 的循环，把队列里的事件取出来分发。同步调用 `sendEvent` 会卡进 `NSTableView` 的跟踪循环等抬起，而抬起要等下一次 `nextEvent`，死锁，只能靠看门狗退出。

正解是让 `NSApp.run()` 跑自己的事件循环，测量逻辑用 `DispatchQueue.main.async` 串成状态机，每一击之间把控制权还给 AppKit。这也是整个程序写成 `NSApplicationDelegate` 而不是线性脚本的原因。

## 4. 量到哪一步为止

计时窗口是 `table.mouseDown` 进入，到「该行进了选中集 + `window.displayIfNeeded()` 返回」。中间的字面工作量：命中测试 → 选中集改写 → 受影响的旧行与新行重绘。

不含显卡合成与垂直同步，和人眼看到像素的时间有差距。这一点要写在 `bench-click.sh` 尾注和 bench-history 里，不能让人以为这是端到端延迟。

等待选中落地用的是 `DispatchQueue.main.async` 轮询选中集，`asyncAfter(0.001)` 兜底：固定时长要么放过慢 case，要么白等。轮询上限 2 秒，超了就记 `missed`。

## 5. 为什么点第 2 列、点可视区内的行

第 1 列在 wide 表里可能是行号列或很窄的列，点它命中不稳定。第 2 列是数据列，任何数据集上都存在（`numberOfColumns > 1` 才取 1，否则退回 0）。

行数取 `contentView.bounds.height / rowHeight`，只点可视区内的行，避免点到滚动区外触发自动滚动，那会把另一种耗时混进来。热身点一次，把首帧懒加载排除在统计之外。

## 6. 结果怎么拿到

装进 .app 之后 stdout 不可靠（`open` 拉起的进程输出会丢）。程序支持 `TW_CLICK_OUT=<路径>` 把一行 `mean= p50= p95= max= over50= missed=` 写到文件，`bench-click.sh` 以文件为准解析，stdout 只当人看的。

同一份数据里 `TW_CLICK_DEBUG=1` 会打命中行、命中列、命中视图类型、key 状态、首响应者 —— 用来排查「又没选中」是哪一步断的。

## 7. 超时保护

`Thread.detachNewThread` 起一个 120 秒看门狗，到点 `exit(3)`。事件跟踪循环这类挂死不会有栈可看，没有看门狗就只能靠人发现终端不动了。

## 风险

- 数字受机器负载影响明显。跑基准前关掉大编译。
- 只点单行单击，不覆盖双击、拖选、shift 连选、键盘移动。验收原话就是「点击一行」。
- 只测网格层的选中，不含工具栏、检查器面板因此重算的连带开销（那部分走的是另一条异步路径）。

