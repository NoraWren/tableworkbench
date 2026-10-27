import AppKit
import SwiftUI
import DuckDBKit
import Features
import DataGrid
import IOKit.pwr_mgt

// 点击基准：往网格上真发一次鼠标按下与抬起，量「按下 → 选中态落地并重绘完」的耗时。
// 口径是应用侧的主线程工作量：事件排队、分发、命中测试、NSTableView 选中改写、
// 受影响行的重绘。不含显卡合成与垂直同步，也不含人手反应时间。

let debug = ProcessInfo.processInfo.environment["TW_CLICK_DEBUG"] != nil
let outPath = ProcessInfo.processInfo.environment["TW_CLICK_OUT"]
// 用 open 拉起时 stderr 落到 launchd，看不到；调试信息同时写一份文件。
let logPath = ProcessInfo.processInfo.environment["TW_CLICK_LOG"]

func log(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    if let logPath {
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(Data((text + "\n").utf8))
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: Data((text + "\n").utf8))
        }
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    log("用法: TableWorkbenchClickBench <文件路径> [点击次数]")
    exit(2)
}
let fileURL = URL(fileURLWithPath: arguments[1])
let clickCount = arguments.count > 2 ? (Int(arguments[2]) ?? 30) : 30

func findScrollView(in view: NSView) -> NSScrollView? {
    if let scrollView = view as? NSScrollView { return scrollView }
    for child in view.subviews {
        if let found = findScrollView(in: child) { return found }
    }
    return nil
}

final class Runner: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var host: NSView!
    var table: NSTableView!
    var scrollView: NSScrollView!
    var session: OpenedFile!

    var lastSelection = IndexSet()
    var rowsToClick: [Int] = []
    var costs: [Double] = []
    var missed = 0
    var reactivations = 0
    var clickIndex = 0
    var warmup = true
    var started = 0.0
    var spinCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 先让启动期的激活事件跑完，再建窗口。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.start() }
    }

    // MARK: - 准备

    func start() {
        let opened: OpenedFile
        do {
            opened = try FileImporter.open(url: fileURL)
        } catch {
            log("打开失败: \(error)")
            exit(1)
        }
        session = opened
        let session = opened.session
        let columns = session.displayColumns

        let grid = DataGridView(
            columns: columns,
            rowCount: session.rowCount,
            sorts: [],
            provider: { offset, size in
                try session.block(offset: offset, size: size, columns: columns)
            },
            onSelectionChange: { [weak self] rows in
                self?.lastSelection = rows
            },
            onError: { _ in }
        )

        let hosting = NSHostingView(rootView: grid)
        hosting.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        host = hosting

        window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        // 浮动层：测量期间别被别的窗口盖住或抢走键盘焦点。
        window.level = .floating
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)

        waitForGrid(deadline: Date().addingTimeInterval(30))
    }

    func waitForGrid(deadline: Date) {
        if let found = findScrollView(in: host),
           let candidate = found.documentView as? NSTableView,
           candidate.numberOfRows > 0, candidate.numberOfColumns > 0 {
            table = candidate
            scrollView = found
            waitForActivation(deadline: Date().addingTimeInterval(20))
            return
        }
        if Date() > deadline {
            log("没有找到网格")
            exit(1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.waitForGrid(deadline: deadline)
        }
    }

    // 点击只有在 key window 里才走正常选中路径。裸进程激活不了，
    // 所以程序必须从 .app 启动，这里只负责等激活真正完成。
    func waitForActivation(deadline: Date) {
        if NSApp.isActive, window.isKeyWindow {
            if debug { log("调试: 激活完成 app=\(NSApp.isActive) key=\(window.isKeyWindow)") }
            prepare()
            return
        }
        if Date() > deadline {
            log("失败: 窗口没能成为 key window（app 激活=\(NSApp.isActive) key=\(window.isKeyWindow)）")
            log("提示: 必须以 build/ClickBench.app 形式启动，直接跑可执行文件拿不到焦点")
            exit(1)
        }
        if !NSApp.isActive {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.waitForActivation(deadline: deadline)
        }
    }

    func prepare() {
        window.makeFirstResponder(table)

        let rowHeight = table.rowHeight + table.intercellSpacing.height
        let visibleRows = max(1, Int(scrollView.contentView.bounds.height / rowHeight))
        rowsToClick = Array(0..<min(visibleRows, max(1, table.numberOfRows)))
        guard !rowsToClick.isEmpty else {
            log("网格里没有可点的行")
            exit(1)
        }

        // 热身：首帧懒加载、首次选中样式不该算进统计。
        click(row: rowsToClick[0], isWarmup: true)
    }

    // MARK: - 点击

    func makeEvent(_ type: NSEvent.EventType, at pointInWindow: NSPoint, number: Int) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: pointInWindow,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: number,
            clickCount: 1,
            pressure: type == .leftMouseDown ? 1 : 0
        )
    }

    func click(row: Int, isWarmup: Bool) {
        let rowRect = table.rect(ofRow: row)
        let columnIndex = table.numberOfColumns > 1 ? 1 : 0
        let columnRect = table.rect(ofColumn: columnIndex)
        let pointInTable = NSPoint(x: columnRect.midX, y: rowRect.midY)
        let pointInWindow = table.convert(pointInTable, to: nil)
        if debug {
            let hit = window.contentView?.hitTest(window.contentView!.convert(pointInWindow, from: nil))
            log("调试: 目标行 \(row) 命中行 \(table.row(at: pointInTable)) 命中列 \(table.column(at: pointInTable)) 命中视图 \(type(of: hit as Any)) key=\(window.isKeyWindow) 首响应者=\(type(of: window.firstResponder as Any))")
        }

        lastSelection = []
        table.deselectAll(nil)
        window.makeFirstResponder(table)

        let stamp = Int(ProcessInfo.processInfo.systemUptime * 1000)
        guard let down = makeEvent(.leftMouseDown, at: pointInWindow, number: stamp),
              let up = makeEvent(.leftMouseUp, at: pointInWindow, number: stamp + 1) else {
            log("造不出鼠标事件")
            exit(1)
        }

        // 按下与抬起都排进应用队列，交给 NSApp 自己的事件循环分发。
        // 直接调 window.sendEvent 会卡进 NSTableView 的事件跟踪循环里等抬起。
        // 先把上一击可能残留的鼠标事件清掉：残留的抬起会把这一击的跟踪循环立刻结束。
        NSApp.discardEvents(matching: [.leftMouseDown, .leftMouseUp], before: nil)
        NSApp.postEvent(down, atStart: false)
        NSApp.postEvent(up, atStart: false)

        started = CFAbsoluteTimeGetCurrent()
        // 直接投给 NSTableView：它内部的事件跟踪循环会从队列里拿到刚排好的抬起事件。
        // 绕开 NSWindow.sendEvent 的「非 key window 先激活窗口」检查 ——
        // 测量机一旦被系统压到后台，那一击就整个被吞掉了。
        table.mouseDown(with: down)
        spinCount = 0
        awaitSelection(row: row, isWarmup: isWarmup, deadline: Date().addingTimeInterval(2))
    }

    // 回到应用自己的事件循环，让排队的点击被分发，再检查选中是否落地。
    func awaitSelection(row: Int, isWarmup: Bool, deadline: Date) {
        if table.selectedRowIndexes.contains(row), lastSelection.contains(row) {
            let landedAt = CFAbsoluteTimeGetCurrent()
            window.displayIfNeeded()
            let cost = (landedAt - started) * 1000
            if isWarmup {
                if debug { log(String(format: "调试: 热身 %.2f ms", cost)) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.nextClick() }
                return
            }
            if debug {
                log(String(format: "调试: 第 %d 击 选中 %@ 回调 %@ 耗时 %.2f ms", clickIndex,
                           "\(table.selectedRowIndexes)", "\(lastSelection)", cost))
            }
            costs.append(cost)
            clickIndex += 1
            nextClick()
            return
        }

        if Date() > deadline {
            let cost = (CFAbsoluteTimeGetCurrent() - started) * 1000
            if isWarmup {
                log(String(format: "失败: 热身点击没有选中（等了 %.0f ms）", cost))
                exit(1)
            }
            missed += 1
            if debug {
                log(String(format: "调试: 第 %d 击未选中（等了 %.0f ms）选中=%@ app激活=%@ key=%@ 首响应者=%@",
                           clickIndex, cost, "\(table.selectedRowIndexes)",
                           "\(NSApp.isActive)", "\(window.isKeyWindow)",
                           "\(type(of: window.firstResponder as Any))"))
            }
            costs.append(cost)
            clickIndex += 1
            nextClick()
            return
        }

        // 前几百次用紧凑的 async 轮询，之后放慢，避免长时间空转。
        spinCount += 1
        if spinCount < 200 {
            DispatchQueue.main.async { self.awaitSelection(row: row, isWarmup: isWarmup, deadline: deadline) }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
                self.awaitSelection(row: row, isWarmup: isWarmup, deadline: deadline)
            }
        }
    }

    func nextClick() {
        if clickIndex >= clickCount {
            finish()
            return
        }
        // 非 key window 会把这一击当成「激活窗口」，不交给内容视图。
        // 外部应用随时可能抢走焦点，所以每一击之前都确认一遍。
        regainKeyIfNeeded(retries: 100) {
            self.click(row: self.rowsToClick[self.clickIndex % self.rowsToClick.count], isWarmup: false)
        }
    }

    func regainKeyIfNeeded(retries: Int, then action: @escaping () -> Void) {
        if NSApp.isActive, window.isKeyWindow {
            action()
            return
        }
        if retries <= 0 {
            log("失败: 连续 5 秒抢不回窗口焦点，测量环境不成立")
            exit(1)
        }
        if reactivations == 0 || retries == 100 { reactivations += 1 }
        NSApp.activate()
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.regainKeyIfNeeded(retries: retries - 1, then: action)
        }
    }

    // MARK: - 结果

    func finish() {
        let sorted = costs.sorted()
        func percentile(_ p: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            let index = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * p)))
            return sorted[index]
        }
        let mean = costs.reduce(0, +) / Double(max(1, costs.count))
        let overBudget = costs.filter { $0 > 50 }.count

        print("文件: \(fileURL.lastPathComponent)  行: \(table.numberOfRows)  列: \(table.numberOfColumns)")
        print("点击 \(costs.count) 次，每次点中第 2 列的一行")
        print(String(format: "按下到选中态重绘完 均值 %.2f ms  中位 %.2f ms  p95 %.2f ms  最大 %.2f ms",
                     mean, percentile(0.5), percentile(0.95), sorted.last ?? 0))
        print(String(format: "超过 50 ms 的点击: %d（%.1f%%）", overBudget,
                     Double(overBudget) / Double(max(1, costs.count)) * 100))
        if missed > 0 { print("选中没生效的点击: \(missed)") }
        if reactivations > 0 { print("中途重新激活应用的次数: \(reactivations)") }

        if let outPath {
            let line = String(format: "mean=%.3f p50=%.3f p95=%.3f max=%.3f over50=%d missed=%d",
                              mean, percentile(0.5), percentile(0.95), sorted.last ?? 0, overBudget, missed)
            try? line.write(toFile: outPath, atomically: true, encoding: .utf8)
        }

        session.session.close()
        exit(missed > 0 ? 1 : 0)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)

// 测量期间不许熄屏、不许进休眠：一旦显示器睡下去，窗口就丢 key，
// 点击会被吞掉，跑出来的就是假数据（实测在第 31 击左右集中出现）。
var assertionID = IOPMAssertionID(0)
let asserted = IOPMAssertionCreateWithName(
    kIOPMAssertionTypeNoDisplaySleep as CFString,
    IOPMAssertionLevel(kIOPMAssertionLevelOn),
    "TableWorkbenchClickBench" as CFString,
    &assertionID
) == kIOReturnSuccess
if !asserted { log("警告: 没能禁止显示器休眠，测量期间可能丢焦点") }

// 挂死保险：事件跟踪循环这类问题没有栈可看，留着这个就不会挂到天亮。
Thread.detachNewThread {
    Thread.sleep(forTimeInterval: 180)
    FileHandle.standardError.write(Data("超时：180 秒内没跑完，先杀掉\n".utf8))
    exit(3)
}

let runner = Runner()
app.delegate = runner
app.run()

