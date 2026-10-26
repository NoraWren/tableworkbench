import Foundation
import DuckDBKit
import Features

struct BenchResult: Encodable {
    let file: String
    let bytes: Int
    let encoding: String
    let columns: Int
    let rows: Int
    let resultRows: Int
    let firstCell: String?
    let openSeconds: Double
    let querySeconds: Double?
    let blocks: [BlockTiming]
}

struct BlockTiming: Encodable {
    let block: Int
    let seconds: Double
    let rows: Int
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("用法: TableWorkbenchBench <文件路径> [--json]\n".utf8))
    exit(2)
}

let url = URL(fileURLWithPath: arguments[1])
let asJSON = arguments.contains("--json")

var sortColumn: String?
var sortAscending = true
var filterColumn: String?
var filterValue: String?
var repeatCount = 1
var sqlStatement: String?
var warmCache = false
var pivotBench = false
var statsColumn: String?
var printValues = false
var argumentIndex = 2
while argumentIndex < arguments.count {
    switch arguments[argumentIndex] {
    case "--sort":
        if argumentIndex + 1 < arguments.count {
            sortColumn = arguments[argumentIndex + 1]
            argumentIndex += 2
        } else {
            argumentIndex += 1
        }
    case "--desc":
        sortAscending = false
        argumentIndex += 1
    case "--stats":
        if argumentIndex + 1 < arguments.count {
            statsColumn = arguments[argumentIndex + 1]
            argumentIndex += 2
        } else {
            argumentIndex += 1
        }
    case "--pivot":
        pivotBench = true
        argumentIndex += 1
    case "--warm-cache":
        warmCache = true
        argumentIndex += 1
    case "--sql":
        if argumentIndex + 1 < arguments.count {
            sqlStatement = arguments[argumentIndex + 1]
            argumentIndex += 2
        } else {
            argumentIndex += 1
        }
    case "--repeat":
        if argumentIndex + 1 < arguments.count {
            repeatCount = max(1, Int(arguments[argumentIndex + 1]) ?? 1)
            argumentIndex += 2
        } else {
            argumentIndex += 1
        }
    case "--values":
        printValues = true
        argumentIndex += 1
    case "--filter":
        if argumentIndex + 1 < arguments.count, let separator = arguments[argumentIndex + 1].firstIndex(of: "=") {
            let pair = arguments[argumentIndex + 1]
            filterColumn = String(pair[..<separator])
            filterValue = String(pair[pair.index(after: separator)...])
        }
        argumentIndex += 2
    default:
        argumentIndex += 1
    }
}

do {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let bytes = (attributes[.size] as? NSNumber)?.intValue ?? 0

    let start = Date()
    let opened = try FileImporter.open(url: url)
    let openSeconds = Date().timeIntervalSince(start)
    if warmCache {
        let cacheStart = Date()
        var ready = false
        while Date().timeIntervalSince(cacheStart) < 120 {
            if ParquetCache.shared.cachedURL(for: url, variant: opened.cacheVariant) != nil {
                ready = true
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        print(String(format: "缓存生成: %.3f 秒 (成功: %@)", Date().timeIntervalSince(cacheStart), ready ? "是" : "否"))
    }

    let firstBlock = try opened.session.block(offset: 0, size: 1)
    let firstRow = firstBlock.rows.first ?? []
    let firstCell: String? = firstRow.first ?? nil

    if let statsColumn {
        let started = Date()
        let stats = try opened.session.columnStats(column: statsColumn)
        print("统计: \(stats.totalRows) 行, 空值 \(stats.nullCount), 去重 \(stats.distinctCount), 耗时 \(String(format: "%.3f", Date().timeIntervalSince(started))) 秒, 直方图 \(stats.histogram.count) 桶")
        exit(0)
    }

    if pivotBench {
        let spec = PivotSpec(
            rows: ["区域", "渠道"],
            columns: ["状态"],
            values: [PivotValue(column: "金额", aggregate: .sum)]
        )
        let result = try opened.session.pivot(spec: spec)
        print("透视: \(result.rowCount) 行, \(String(format: "%.3f", result.elapsed)) 秒, 列数 \(result.columns.count)")
        exit(0)
    }

    if let sqlStatement {
        let result = try opened.session.runSQL(sqlStatement)
        print("SQL: \(result.rowCount) 行, \(String(format: "%.3f", result.elapsed)) 秒, 截断: \(result.truncated)")
        if printValues {
            for row in result.rows.prefix(12) {
                print("  " + row.map { $0 ?? "NULL" }.joined(separator: " | "))
            }
        }
        exit(0)
    }

    var querySeconds: Double?
    if sortColumn != nil || filterColumn != nil {
        let sort = sortColumn.map { [SortSpec(column: $0, ascending: sortAscending)] } ?? []
        let filter = filterColumn.map {
            FilterGroup(join: .and, conditions: [FilterCondition(column: $0, op: .equal, value: filterValue ?? "")])
        }
        let queryStart = Date()
        for _ in 0..<repeatCount {
            try opened.session.apply(view: QueryView(sort: sort, filter: filter))
        }
        querySeconds = Date().timeIntervalSince(queryStart)
    }

    var timings: [BlockTiming] = []
    for blockIndex in [0, 9, 99] {
        let offset = blockIndex * QuerySessionDefaults.blockSize
        guard offset < opened.session.resultCount else { continue }
        let blockStart = Date()
        let block = try opened.session.block(offset: offset, size: QuerySessionDefaults.blockSize)
        timings.append(BlockTiming(block: blockIndex + 1, seconds: Date().timeIntervalSince(blockStart), rows: block.rows.count))
    }

    let result = BenchResult(
        file: url.lastPathComponent,
        bytes: bytes,
        encoding: opened.encoding.displayName,
        columns: opened.session.columns.count,
        rows: opened.session.rowCount,
        resultRows: opened.session.resultCount,
        firstCell: firstCell,
        openSeconds: openSeconds,
        querySeconds: querySeconds,
        blocks: timings
    )

    if asJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(result), as: UTF8.self))
    } else {
        print("文件: \(result.file) (\(bytes / 1024 / 1024) MB)")
        print("编码: \(result.encoding)  列: \(result.columns)  行: \(result.rows)  结果: \(result.resultRows)")
        print("首行: \(result.firstCell ?? "nil")")
        print(String(format: "打开: %.3f 秒", result.openSeconds))
        if let querySeconds = result.querySeconds {
            print(String(format: "查询准备: %.3f 秒", querySeconds))
        }
        for timing in result.blocks {
            print(String(format: "第 %d 块: %.3f 秒 (%d 行)", timing.block, timing.seconds, timing.rows))
        }
    }
    exit(0)
} catch let error as ImportError {
    FileHandle.standardError.write(Data(("打开失败: \(error.userMessage)\n").utf8))
    if let detail = error.technicalDetail {
        FileHandle.standardError.write(Data(("\(detail)\n").utf8))
    }
    exit(1)
} catch {
    FileHandle.standardError.write(Data(("打开失败: \(error)\n").utf8))
    exit(1)
}
