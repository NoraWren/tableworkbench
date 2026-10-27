import Foundation
import DuckDBKit
import Features

// 内存基准（R-PERF-06）。
//
// 用法：
//   TableWorkbenchMemoryBench cycle <文件…> [--rounds N] [--settle 秒] [--sort] [--verbose]
//       连续开/关大文件，看内存能不能回到基线附近。
//   TableWorkbenchMemoryBench idle <秒数> [文件]
//       打开一个文件后不再动它，看静置期间内存涨不涨。
//
// 口径说明（为什么判定用匿名页，而不是 RSS）：
//   RSS 里混着读文件留下的页缓存。1 GB 的 Parquet 读一遍，RSS 就能被顶到 2 GB，
//   那部分是系统缓存、随时可回收的干净页，不是应用自己占着的内存。
//   这里判定只看 task_vm_info.internal（匿名页），和活动监视器的「内存」列同源；
//   external（文件页）和 RSS 一并打印作参考，不参与判定。
//
// 为什么判定前要静置：
//   开关文件时 DuckDB 会申请一批工作内存，关掉会话后这些页由分配器继续持有，
//   不是立刻还给系统。实测 20 次开关后匿名页一度到 372 MB，静置 11 秒落到 43 MB、
//   最终 26 MB（RSS 131 MB）。如果在最后一步操作后立刻采样，量到的是还没回收的高水位，
//   会把「晚一点就还回去」误判成泄漏。所以每轮都采一次用于观察趋势，判定取静置后的稳态值。
//
// 为什么要先热身：
//   第一次打开会把 DuckDB 引擎、线程池和类型系统装进来，这是一次性开销。
//   基线取「每个文件都开过一遍之后」的空载值，之后每一轮再开同样的文件，比较的才是「开关有没有多占内存」。

// MARK: - 采样

func vmInfo() -> task_vm_info_data_t? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info : nil
}

/// 匿名页，判定用的就是这个数。
func anonymousMB() -> Double {
    guard let info = vmInfo() else { return -1 }
    return Double(info.internal) / 1024 / 1024
}

/// 文件页：读 CSV/Parquet 时由系统缓存，内存紧张时随时回收。
func filePagesMB() -> Double {
    guard let info = vmInfo() else { return -1 }
    return Double(info.external) / 1024 / 1024
}

func rssMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Double(info.resident_size) / 1024 / 1024 : -1
}

// MARK: - 开关一个文件

/// 等后台的 Parquet 转换落地，避免多个转换任务同时挂在内存里。
func waitForConversion() {
    let deadline = Date().addingTimeInterval(180)
    while Date() < deadline {
        let names = (try? FileManager.default.contentsOfDirectory(
            at: ParquetCache.shared.baseDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        if !names.contains(where: { $0.lastPathComponent.hasSuffix(".parquet.tmp") }) { return }
        Thread.sleep(forTimeInterval: 0.2)
    }
}

/// 界面一次最多画多少列，和 DataGridView.visibleColumns 的上限对齐。
let visibleColumnLimit = 200

/// 打开、读首块、读第一列的统计，再关掉。和用户「点开看一眼再关」走同一条路径。
/// 排序单独用 withSort 控制：排序会把结果物化成一张临时表，是另一回事。
@discardableResult
func openAndClose(_ path: String, withSort: Bool = false) -> Bool {
    let url = URL(fileURLWithPath: path)
    do {
        let opened = try FileImporter.open(url: url)
        let session = opened.session
        // 和用户点关闭同一条路径：离开作用域就关连接，中途报错也不漏。
        defer { session.close() }
        let columns = Array(session.displayColumns.prefix(visibleColumnLimit))
        _ = try session.block(offset: 0, size: 500, columns: columns)
        if let first = columns.first {
            if withSort {
                try session.apply(view: QueryView(
                    sort: [SortSpec(column: first.name, ascending: true)],
                    filter: nil
                ))
                _ = try session.block(offset: 0, size: 500)
            }
            _ = try session.columnStats(column: first.name)
        }
        return true
    } catch {
        FileHandle.standardError.write(Data("打开失败 \(path): \(error)\n".utf8))
        return false
    }
}

/// CSV/TSV 首次打开会排一次后台转 Parquet，等它落地再进下一个。
func settle(_ path: String) {
    let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
    if ext == "csv" || ext == "tsv" { waitForConversion() }
}

func shortName(_ path: String) -> NSString {
    (path as NSString).lastPathComponent as NSString
}

// MARK: - 入口

// 输出逐行刷新：静置类基准要跑半小时，缓冲住就没法边跑边看了。
setvbuf(stdout, nil, _IOLBF, 0)

let arguments = CommandLine.arguments
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(2)
}

func intOption(_ name: String, default fallback: Int) -> Int? {
    guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return fallback }
    guard let value = Int(arguments[i + 1]) else { return nil }
    return value
}

guard arguments.count >= 2 else {
    fail("""
    用法：
      TableWorkbenchMemoryBench cycle <文件…> [--rounds N] [--settle 秒] [--sort] [--verbose]
      TableWorkbenchMemoryBench idle <秒数> [文件]
    """)
}

switch arguments[1] {
case "cycle":
    var paths: [String] = []
    var rounds = 1
    var withSort = false
    var verbose = false
    var index = 2
    while index < arguments.count {
        if arguments[index] == "--rounds", index + 1 < arguments.count {
            guard let value = Int(arguments[index + 1]) else { fail("--rounds 需要一个整数") }
            rounds = max(1, value)
            index += 2
        } else if arguments[index] == "--settle", index + 1 < arguments.count {
            index += 2
        } else if arguments[index] == "--sort" {
            withSort = true
            index += 1
        } else if arguments[index] == "--verbose" {
            verbose = true
            index += 1
        } else {
            paths.append(arguments[index])
            index += 1
        }
    }
    guard !paths.isEmpty else { fail("至少给一个文件") }
    guard let settleSeconds = intOption("--settle", default: 30), settleSeconds >= 0 else {
        fail("--settle 需要一个非负整数")
    }

    // 先把每个文件都开一遍：引擎和线程池装进来，CSV 的 Parquet 缓存也生成好。
    // 基线取这一步之后的空载值，之后的每一轮才算「重复开关多占了多少」。
    let coldStart = anonymousMB()
    var warmFailed = 0
    for path in paths {
        if !openAndClose(path, withSort: withSort) { warmFailed += 1 }
        settle(path)
    }
    Thread.sleep(forTimeInterval: 2)
    let idleBaseline = anonymousMB()
    print(String(format: "冷启动匿名 %.0f MB｜每个文件热过一次后空载基线 %.0f MB（一次性抬升 %+.0f）",
                 coldStart, idleBaseline, idleBaseline - coldStart))
    print(String(format: "计划：%d 个文件 × %d 轮 = %d 次开关%@",
                 paths.count, rounds, paths.count * rounds, withSort ? "（每轮含一次排序）" : ""))

    var samples: [Double] = []
    var peak = idleBaseline
    var failed = warmFailed
    for round in 1...rounds {
        for path in paths {
            let before = anonymousMB()
            if !openAndClose(path, withSort: withSort) { failed += 1 }
            settle(path)
            if verbose {
                let after = anonymousMB()
                print(String(format: "    %-18@ 匿名 %5.0f → %5.0f（%+5.0f）｜文件页 %5.0f｜RSS %5.0f",
                             shortName(path), before, after, after - before,
                             filePagesMB(), rssMB()))
            }
        }
        // 给后台线程一点时间收尾再采样。
        Thread.sleep(forTimeInterval: 1)
        let now = anonymousMB()
        samples.append(now)
        peak = max(peak, now)
        print(String(format: "第 %2d 轮后 匿名 %5.0f MB｜文件页 %5.0f MB｜RSS %5.0f MB",
                     round, now, filePagesMB(), rssMB()))
    }

    // 静置：关会话后分配器持有的页要过一会儿才还给系统，等它落定再判定。
    var settled = anonymousMB()
    if settleSeconds > 0 {
        print("")
        print("静置 \(settleSeconds) 秒等内存落定（每 5 秒采一次）")
        var waited = 0
        while waited < settleSeconds {
            Thread.sleep(forTimeInterval: Double(min(5, settleSeconds - waited)))
            waited = min(waited + 5, settleSeconds)
            settled = anonymousMB()
            peak = max(peak, settled)
            print(String(format: "  +%3d 秒  匿名 %5.0f MB（相对基线 %+5.0f）｜RSS %5.0f MB",
                         waited, settled, settled - idleBaseline, rssMB()))
        }
        samples.append(settled)
    }

    let limit = 200.0
    let final = samples.last ?? idleBaseline
    let firstRound = samples.first ?? idleBaseline
    print("")
    print(String(format: "空载基线 %.0f MB，静置后落点 %.0f MB（%+.0f），允许上限 +%.0f",
                 idleBaseline, final, final - idleBaseline, limit))
    print(String(format: "第 1 轮 %.0f MB → 稳态 %.0f MB（%+.0f），全程峰值 %.0f MB（%+.0f）",
                 firstRound, final, final - firstRound, peak, peak - idleBaseline))
    if failed > 0 {
        print("判定: 未通过，有 \(failed) 个文件没打开成功")
        exit(1)
    }
    // 只卡上限：静置后比基线低是好事，不算失败。
    if final - idleBaseline <= limit {
        print("判定: 通过")
        exit(0)
    }
    print("判定: 未通过，静置后内存没有回到基线附近")
    exit(1)

case "idle":
    var secondsArg: Int?
    var target: String?
    var position = 2
    while position < arguments.count {
        if arguments[position] == "--seconds", position + 1 < arguments.count {
            secondsArg = Int(arguments[position + 1])
            position += 2
        } else if secondsArg == nil, let value = Int(arguments[position]) {
            secondsArg = value
            position += 1
        } else {
            target = arguments[position]
            position += 1
        }
    }
    guard let secondsValue = secondsArg, secondsValue > 0 else {
        fail("用法：TableWorkbenchMemoryBench idle <秒数> [文件]")
    }
    let seconds = Double(secondsValue)

    // 有文件就先打开并保持打开：用户真实场景是「打开一个大文件，然后去开会」。
    var held: QuerySession?
    if let target {
        do {
            let opened = try FileImporter.open(url: URL(fileURLWithPath: target))
            held = opened.session
            _ = try opened.session.block(
                offset: 0,
                size: 500,
                columns: Array(opened.session.displayColumns.prefix(visibleColumnLimit))
            )
            if let first = opened.session.displayColumns.first {
                _ = try opened.session.columnStats(column: first.name)
            }
            print("已打开 \(shortName(target))，保持打开状态静置")
        } catch {
            fail("打开 \(target) 失败：\(error)")
        }
    }
    defer { held?.close() }

    let interval = min(60.0, max(1.0, seconds / 20))
    // 起始值也取静置几秒之后的：刚打开文件时分配器还在往回还页，那不是「上涨」。
    Thread.sleep(forTimeInterval: min(10, max(2, interval)))
    let start = anonymousMB()
    print(String(format: "静置 %.0f 秒，起始匿名 %.0f MB（文件页 %.0f MB，RSS %.0f MB），每 %.0f 秒采一次",
                 seconds, start, filePagesMB(), rssMB(), interval))
    var samples: [Double] = [start]
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        let slice = min(interval, deadline.timeIntervalSinceNow)
        guard slice > 0 else { break }
        Thread.sleep(forTimeInterval: slice)
        let now = anonymousMB()
        samples.append(now)
        print(String(format: "  +%4.0f 秒  匿名 %5.0f MB（相对起始 %+5.0f）｜RSS %5.0f MB",
                     seconds - deadline.timeIntervalSinceNow, now, now - start, rssMB()))
    }
    let end = samples.last ?? start
    let growth = end - start
    let peakGrowth = (samples.max() ?? start) - start
    print("")
    print(String(format: "末值 %.0f MB，相对起始 %+.0f MB，最大相对涨幅 %+.0f MB",
                 end, growth, peakGrowth))
    // 「不上涨」的口径：末值和全程最高点都不得比起始高 20 MB。
    let allowed = 20.0
    if growth <= allowed && peakGrowth <= allowed {
        print("判定: 通过")
        exit(0)
    }
    print("判定: 未通过，静置期间内存上涨")
    exit(1)

default:
    fail("未知子命令 \(arguments[1])")
}

