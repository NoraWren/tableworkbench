import Foundation
import CryptoKit
import Darwin
import DuckDBKit
import Features
import DataGrid

var failures = 0

func check(_ name: String, _ condition: Bool) {
    if condition {
        print("PASS  \(name)")
    } else {
        failures += 1
        print("FAIL  \(name)")
    }
}

func residentMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Double(info.resident_size) / 1024 / 1024 : -1
}

func expectThrows(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
        failures += 1
        print("FAIL  \(name)（没有抛错）")
    } catch {
        print("PASS  \(name)")
    }
}

func run() throws {
    // 编码探测
    check("UTF-8 识别", EncodingDetector.detect(sample: "客户,金额".data(using: .utf8)!) == .utf8)
    var bom = Data([0xEF, 0xBB, 0xBF])
    bom.append("客户,金额".data(using: .utf8)!)
    check("BOM 识别", EncodingDetector.detect(sample: bom) == .utf8BOM)
    check("GB18030 识别", EncodingDetector.detect(sample: "客户,金额".data(using: EncodingDetector.gb18030)!) == .gb18030)

    // CSV 嗅探
    let comma = CSVSniffer.sniff(sample: "名称,金额\n张三,1.5", fileExtension: "csv")
    check("逗号分隔", comma.delimiter == ",")
    check("识别表头", comma.hasHeader)
    let tab = CSVSniffer.sniff(sample: "1\t2\n3\t4", fileExtension: "tsv")
    check("制表符分隔", tab.delimiter == "\t")
    check("无表头", !tab.hasHeader)
    check(
        "列名清洗",
        CSVSniffer.sanitizeColumnNames(["客户 名称（全称）", "", "a", "a"]) == ["客户_名称_全称", "column_2", "a", "a_2"]
    )

    // 只读校验
    expectThrows("DROP 被拒绝") { try SQLGuard.validate("DROP TABLE data") }
    expectThrows("delete 被拒绝") { try SQLGuard.validate("delete from data") }
    check("SELECT 放行", (try? SQLGuard.validate("SELECT * FROM data LIMIT 10")) != nil)
    check("字符串里的关键字不误伤", (try? SQLGuard.validate("SELECT 'drop delete' AS note FROM data")) != nil)

    // 块缓存
    let cache = BlockCache(capacity: 2)
    cache.insert(TableBlock(offset: 0, rows: [["a"]]), for: 0)
    cache.insert(TableBlock(offset: 5, rows: [["b"]]), for: 1)
    _ = cache.value(for: 0)
    cache.insert(TableBlock(offset: 10, rows: [["c"]]), for: 2)
    check("LRU 淘汰最旧块", cache.value(for: 1) == nil && cache.value(for: 0) != nil && cache.cachedCount == 2)

    // 假实现边界
    let fake = FakeSession(rowCount: 12)
    check("首块 5 行", try fake.block(offset: 0, size: 5).rows.count == 5)
    check("尾块 2 行", try fake.block(offset: 10, size: 5).rows.count == 2)
    check("越界为空", try fake.block(offset: 20, size: 5).rows.isEmpty)

    // 真实链路
    let working = FileManager.default.temporaryDirectory.appendingPathComponent("tw-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: working, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: working) }

    let csv = working.appendingPathComponent("sample.csv")
    let csvText = "客户名称,金额,备注\n张三,1280.50,首单\n李四,980.00,\n王五,2400.75,\"含,逗号\"\n赵六,10.00,\"\"\n"
    try csvText.write(to: csv, atomically: true, encoding: .utf8)

    let before = SHA256.hash(data: try Data(contentsOf: csv))
    let opened = try FileImporter.open(url: csv)
    check("真实行数 4", opened.session.rowCount == 4)
    check("真实列数 3", opened.session.columns.count == 3)
    check("列名清洗生效", opened.session.columns[0].displayName == "客户名称")
    check("金额识别为数值", opened.session.columns[1].kind.isNumeric)

    let block = try opened.session.block(offset: 0, size: 2)
    check("真实块 2 行", block.rows.count == 2)
    check("首行客户", block.rows.first?.first == "张三")
    check("未加引号的空字段是 NULL", block.rows[1][2] == nil)
    let quoted = try opened.session.block(offset: 3, size: 1)
    check("CSV 空字段统一读成 NULL", quoted.rows.first?[2] == nil)

    let after = SHA256.hash(data: try Data(contentsOf: csv))
    check("源文件未被修改", before == after)

    // GBK 链路
    let gbk = working.appendingPathComponent("gbk.csv")
    try "客户名称,金额\n张三,100\n".write(to: gbk, atomically: true, encoding: EncodingDetector.gb18030)
    let gbkOpened = try FileImporter.open(url: gbk)
    check("GBK 行数 1", gbkOpened.session.rowCount == 1)
    check("GBK 列名不乱码", gbkOpened.session.columns[0].displayName == "客户名称")
    check("GBK 编码被记录", gbkOpened.encoding == .gb18030)

    // 连续开关的内存波动（用小文件跑 20 次，验证释放路径）
    let memoryBefore = residentMB()
    for _ in 0..<20 {
        let session = try FileImporter.open(url: csv)
        _ = try session.session.block(offset: 0, size: 10)
        session.session.close()
    }
    let memoryAfter = residentMB()
    print(String(format: "内存 20 次开关: %.1f MB -> %.1f MB", memoryBefore, memoryAfter))
    check("20 次开关内存波动小于 200MB", abs(memoryAfter - memoryBefore) < 200)
}

do {
    try run()
    print("")
    if failures == 0 {
        print("全部通过")
        exit(0)
    } else {
        print("失败 \(failures) 项")
        exit(1)
    }
} catch {
    print("FAIL  未捕获错误: \(error)")
    exit(1)
}
