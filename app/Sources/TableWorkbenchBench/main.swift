import Foundation
import DuckDBKit
import Features

struct BenchResult: Encodable {
    let file: String
    let bytes: Int
    let encoding: String
    let columns: Int
    let rows: Int
    let openSeconds: Double
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

do {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let bytes = (attributes[.size] as? NSNumber)?.intValue ?? 0

    let start = Date()
    let opened = try FileImporter.open(url: url)
    let openSeconds = Date().timeIntervalSince(start)

    var timings: [BlockTiming] = []
    for blockIndex in [0, 9, 99] {
        let offset = blockIndex * QuerySessionDefaults.blockSize
        guard offset < opened.session.rowCount else { continue }
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
        openSeconds: openSeconds,
        blocks: timings
    )

    if asJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(result), as: UTF8.self))
    } else {
        print("文件: \(result.file) (\(bytes / 1024 / 1024) MB)")
        print("编码: \(result.encoding)  列: \(result.columns)  行: \(result.rows)")
        print(String(format: "打开: %.3f 秒", result.openSeconds))
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
