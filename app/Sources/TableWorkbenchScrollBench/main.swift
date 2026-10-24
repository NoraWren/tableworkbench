import AppKit
import SwiftUI
import DuckDBKit
import Features
import DataGrid

// 滚动基准：在离屏窗口里把网格按 60Hz 往下滚，量每一次“改偏移 + 布局 + 绘制”的主线程耗时。
// 没有 Xcode 和 Instruments 时，这是唯一能重复跑、能对比改动的帧率口径。

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("用法: TableWorkbenchScrollBench <文件路径> [秒数]\n".utf8))
    exit(2)
}

let url = URL(fileURLWithPath: arguments[1])
let durationSeconds = arguments.count > 2 ? (Double(arguments[2]) ?? 5) : 5

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let opened: OpenedFile
do {
    opened = try FileImporter.open(url: url)
} catch {
    FileHandle.standardError.write(Data("打开失败: \(error)\n".utf8))
    exit(1)
}

let columns = opened.session.displayColumns
let session = opened.session

let grid = DataGridView(
    columns: columns,
    rowCount: session.rowCount,
    sorts: [],
    provider: { offset, size in
        try session.block(offset: offset, size: size, columns: columns)
    },
    onError: { _ in }
)

let host = NSHostingView(rootView: grid)
host.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)

let window = NSWindow(
    contentRect: host.frame,
    styleMask: [.titled, .resizable],
    backing: .buffered,
    defer: false
)
window.contentView = host
window.makeKeyAndOrderFront(nil)

func pump(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
}

func findScrollView(in view: NSView) -> NSScrollView? {
    if let scrollView = view as? NSScrollView { return scrollView }
    for child in view.subviews {
        if let found = findScrollView(in: child) { return found }
    }
    return nil
}

// 等 SwiftUI 把 NSTableView 建出来并完成首屏布局。
var scrollView: NSScrollView?
let readyDeadline = Date().addingTimeInterval(15)
while Date() < readyDeadline {
    pump(0.1)
    if let found = findScrollView(in: host), let table = found.documentView as? NSTableView {
        scrollView = found
        if table.numberOfRows > 0, table.numberOfColumns > 0 { break }
    }
}

guard let scrollView, let table = scrollView.documentView as? NSTableView else {
    FileHandle.standardError.write(Data("没有找到网格\n".utf8))
    exit(1)
}

let clip = scrollView.contentView
clip.postsBoundsChangedNotifications = true
pump(1.0)

func visibleHeight() -> CGFloat { clip.bounds.height }
let stepPerTick: CGFloat = 24
let tickInterval = 1.0 / 60.0
let tickCount = max(1, Int(durationSeconds / tickInterval))

var costs: [Double] = []
costs.reserveCapacity(tickCount)

var offset: CGFloat = 0
var maxOffset = max(0, table.frame.height - visibleHeight())

for _ in 0..<tickCount {
    if offset > maxOffset {
        offset = 0
        maxOffset = max(0, table.frame.height - visibleHeight())
    }

    let started = CFAbsoluteTimeGetCurrent()
    clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: offset))
    window.displayIfNeeded()
    costs.append((CFAbsoluteTimeGetCurrent() - started) * 1000)
    offset += stepPerTick

    // 让出一点时间给事件与显示回调，模拟真实的一帧间隔。
    let nextTick = Date().addingTimeInterval(tickInterval)
    while Date() < nextTick {
        RunLoop.main.run(mode: .default, before: nextTick)
    }
}

let sorted = costs.sorted()
func percentile(_ p: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let index = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * p)))
    return sorted[index]
}

let overBudget = costs.filter { $0 > 16.7 }.count
let mean = costs.reduce(0, +) / Double(max(1, costs.count))

print("文件: \(url.lastPathComponent)  行: \(table.numberOfRows)  列: \(table.numberOfColumns)")
print(String(format: "滚动 %d 次，每次 %.0f 点", costs.count, stepPerTick))
print(String(format: "主线程每帧耗时 均值 %.2f ms  中位 %.2f ms  p95 %.2f ms  最大 %.2f ms",
             mean, percentile(0.5), percentile(0.95), sorted.last ?? 0))
print(String(format: "超过 16.7 ms 的帧: %d（%.1f%%）", overBudget, Double(overBudget) / Double(max(1, costs.count)) * 100))

session.close()
exit(0)
