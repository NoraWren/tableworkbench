# Design

## Context

网格是 NSTableView，取块大小 5000 行，滚动时按需换行视图。滚动卡不卡，取决于主线程能不能在 16.7 毫秒内完成“换可见行 + 布局 + 绘制”。

## Goals / Non-Goals

**Goals:**

- 不需要人工参与，一条命令出数字。
- 换机器、换改动后能直接对比。

**Non-Goals:**

- 测量 GPU 合成与显示器刷新。
- 模拟真实触控板惯性。

## Decisions

### D1 离屏窗口 + 60Hz 定时改偏移

每次循环把 NSScrollView 的 boundsOrigin 下移 24 点，然后 displayIfNeeded()，用 CFAbsoluteTimeGetCurrent 量这一段。这样测到的是应用自己那部分成本；显卡合成和垂直同步不计入，所以是本机口径而不是绝对帧率。

### D2 走真实的 DataGridView

用 NSHostingView 托管真正的 DataGridView，而不是自己拼一个 NSTableView，避免量到的是一份和产品无关的代码。

### D3 输出分位数而不是平均

平均会被少数慢帧抹平。p95 和“超过 16.7 ms 的帧占比”更接近用户感受：偶尔一次 20 毫秒没人看得见，7% 的帧超时就明显发涩。

### 被否决的方案

- 用 AppleScript 或 CGEvent 合成滚动：帧间隔被自动化本身拉长，测出来是自动化器件的速度。
- 只看 CPU 占用：和掉帧没有稳定对应关系。

## 风险

离屏窗口的绘制路径可能比真机省掉一部分合成工作，数字偏乐观。记录里必须写清这一点，并且和真实录屏交叉验证。
