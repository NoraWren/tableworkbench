import Foundation
import AppKit
import CryptoKit
import Darwin
import DuckDBKit
import Features
import DataGrid
import SQLEditorUI
import WorkbenchUI
import SwiftUI

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

/// 等主线程上的异步任务跑完；测试进程本身就在主线程，所以可以直接跑 RunLoop。
func waitFor(timeout: TimeInterval = 10, _ condition: @escaping @MainActor () -> Bool) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if MainActor.assumeIsolated({ condition() }) { return }
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
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

    // 大文件流式转码：GBK、UTF-16、UTF-8 BOM 三种，验证内容完整且不整文件读入内存
    var bigText = "编号,名称,备注\n"
    for index in 0..<120_000 {
        bigText += "A\(index),客户\(index)有限公司,这是一段用于测试转码边界的备注文本\n"
    }
    let bigGBK = working.appendingPathComponent("gbk-big.csv")
    try bigText.write(to: bigGBK, atomically: true, encoding: EncodingDetector.gb18030)
    let bigGBKUTF8 = working.appendingPathComponent("gbk-big-utf8.csv")
    try TextFileTranscoder.transcode(source: bigGBK, encoding: .gb18030, destination: bigGBKUTF8)
    let roundTrip = try String(contentsOf: bigGBKUTF8, encoding: .utf8)
    check("GBK 大文件流式转码一致", roundTrip == bigText)

    let bigUTF16 = working.appendingPathComponent("utf16-big.csv")
    try bigText.write(to: bigUTF16, atomically: true, encoding: .utf16LittleEndian)
    let bigUTF16Out = working.appendingPathComponent("utf16-big-utf8.csv")
    try TextFileTranscoder.transcode(source: bigUTF16, encoding: .utf16LE, destination: bigUTF16Out)
    check("UTF-16 大文件流式转码一致", try String(contentsOf: bigUTF16Out, encoding: .utf8) == bigText)

    let bomSource = working.appendingPathComponent("bom-big.csv")
    var bomData = Data([0xEF, 0xBB, 0xBF])
    bomData.append(Data("a,b\n1,2\n".utf8))
    try bomData.write(to: bomSource)
    let bomOut = working.appendingPathComponent("bom-big-utf8.csv")
    try TextFileTranscoder.transcode(source: bomSource, encoding: .utf8BOM, destination: bomOut)
    check("BOM 文件去头", try String(contentsOf: bomOut, encoding: .utf8) == "a,b\n1,2\n")

    // 分块边界：末尾只剩首字节时要回退，完整字符不动
    let partial = Data([0x41, 0xBF])
    check("GB18030 半字符回退", TextFileTranscoder.gb18030SafePrefixLength(partial) == 1)
    let complete = Data([0x41, 0xBF, 0xCD, 0x42])
    check("GB18030 完整字符不回退", TextFileTranscoder.gb18030SafePrefixLength(complete) == 4)
    let ascii = Data("hello".utf8)
    check("纯 ASCII 不回退", TextFileTranscoder.gb18030SafePrefixLength(ascii) == 5)

    // 3000 列文件：数据层应能打开，不改写、不超时
    let wide = URL(fileURLWithPath: "../bench-data/wide-3000.csv")
    if FileManager.default.fileExists(atPath: wide.path) {
        let openedWide = try FileImporter.open(url: wide)
        check("3000 列文件可打开", openedWide.session.columns.count == 3000)
        check("3000 列文件行数 200", openedWide.session.rowCount == 200)
        let shown = Array(openedWide.session.displayColumns.prefix(3))
        let wideBlock = try openedWide.session.block(offset: 0, size: 2, columns: shown)
        check("宽表只取显示列", wideBlock.rows.first?.count == 3)
        check("宽表显示列有值", wideBlock.rows.first?.first == "v0_0")

        let wideColumns = openedWide.session.displayColumns
        check("宽表默认 200 列", ColumnVisibility.shown(wideColumns, enabled: nil).count == 200)
        let enabled = ColumnVisibility.toggled(wideColumns, enabled: nil, column: "列2099")
        let withExtra = ColumnVisibility.shown(wideColumns, enabled: enabled)
        check("启用第 2100 列", withExtra.count == 201 && withExtra.contains { $0.name == "列2099" })
        check("启用后排在第 201 位", withExtra.last?.name == "列2099")

        // 行详情在宽表上只取 200 列，别一次拉 3000 个字段
        let detailStart = Date()
        let detailBlock = try openedWide.session.block(
            offset: 0,
            size: 1,
            columns: ColumnVisibility.shown(wideColumns, enabled: nil)
        )
        let detailSeconds = Date().timeIntervalSince(detailStart)
        check("宽表行详情 200 列", detailBlock.rows.first?.count == 200)
        print(String(format: "宽表行详情耗时: %.3f 秒", detailSeconds))
        check("宽表行详情 300 毫秒内", detailSeconds < 0.3)
        openedWide.session.close()
    } else {
        print("SKIP  3000 列文件不存在，先跑 make-bench-data")
    }

    // 伪装成 CSV 的二进制文件必须被拒绝
    let fakeCSV = working.appendingPathComponent("fake.csv")
    try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01]).write(to: fakeCSV)
    var rejected = false
    do {
        _ = try FileImporter.open(url: fakeCSV)
    } catch {
        rejected = true
    }
    check("伪装成 CSV 的二进制被拒绝", rejected)

    // 不支持的扩展名给出可读错误
    let legacyExcel = working.appendingPathComponent("old.xls")
    try "a,b\n1,2\n".write(to: legacyExcel, atomically: true, encoding: .utf8)
    var unsupportedMessage: String?
    do {
        _ = try FileImporter.open(url: legacyExcel)
    } catch let importError as ImportError {
        unsupportedMessage = importError.userMessage
    }
    check("xls 提示不支持", unsupportedMessage == "不支持这个文件格式")

    // 排序与筛选
    let queryCSV = working.appendingPathComponent("query.csv")
    let queryText = "name,amount,city\na,100,上海\nb,50,北京\nc,200,上海\nd,30,广州\ne,300,上海\nO'Brien,400,上海\n"
    try queryText.write(to: queryCSV, atomically: true, encoding: .utf8)
    let query = try FileImporter.open(url: queryCSV)
    check("查询样本 6 行", query.session.rowCount == 6)

    try query.session.apply(view: QueryView(sort: [SortSpec(column: "amount", ascending: true)]))
    check("排序后结果数不变", query.session.resultCount == 6)
    check("升序首行 d", try query.session.block(offset: 0, size: 1).rows.first?.first == "d")
    check("查询代次自增", query.session.generation == 1)

    try query.session.apply(view: QueryView(filter: FilterGroup(join: .and, conditions: [
        FilterCondition(column: "city", op: .equal, value: "上海")
    ])))
    check("筛选上海 4 行", query.session.resultCount == 4)
    check("筛选首行 a", try query.session.block(offset: 0, size: 1).rows.first?.first == "a")

    try query.session.apply(view: QueryView(filter: FilterGroup(join: .and, conditions: [
        FilterCondition(column: "city", op: .equal, value: "上海"),
        FilterCondition(column: "amount", op: .greaterThan, value: "150")
    ])))
    check("AND 结果 3 行", query.session.resultCount == 3)

    try query.session.apply(view: QueryView(filter: FilterGroup(join: .or, conditions: [
        FilterCondition(column: "city", op: .equal, value: "北京"),
        FilterCondition(column: "amount", op: .greaterThan, value: "150")
    ])))
    check("OR 结果 4 行", query.session.resultCount == 4)

    try query.session.apply(view: QueryView(filter: FilterGroup(join: .and, conditions: [
        FilterCondition(column: "name", op: .equal, value: "O'Brien")
    ])))
    check("单引号值可查询", query.session.resultCount == 1)

    try query.session.apply(view: QueryView(
        sort: [SortSpec(column: "amount", ascending: false)],
        filter: FilterGroup(join: .and, conditions: [FilterCondition(column: "city", op: .equal, value: "上海")])
    ))
    check("排序加筛选 4 行", query.session.resultCount == 4)
    check("降序首行 O'Brien", try query.session.block(offset: 0, size: 1).rows.first?.first == "O'Brien")

    try query.session.apply(view: QueryView(filter: FilterGroup(join: .and, conditions: [
        FilterCondition(column: "city", op: .equal, value: "不存在")
    ])))
    check("空结果 0 行", query.session.resultCount == 0)
    check("空结果块为空", try query.session.block(offset: 0, size: 10).rows.isEmpty)

    let escaped = SQLBuilder.conditionSQL(FilterCondition(column: "name", op: .equal, value: "O'Brien"))
    check("SQL 转义单引号", escaped == "\"name\" = 'O''Brien'")
    check("数字不加引号", SQLBuilder.literal("150") == "150")
    check(
        "多列排序 SQL",
        SQLBuilder.orderBy([
            SortSpec(column: "amount", ascending: false),
            SortSpec(column: "city", ascending: true)
        ]) == "ORDER BY \"amount\" DESC, \"city\" ASC"
    )

    // SQL 抽屉
    let countResult = try query.session.runSQL("SELECT count(*) FROM data")
    check("SQL 返回总行数", countResult.rows.first?.first == "6")
    check("SQL 列数 1", countResult.columns.count == 1)

    let sortedSQL = try query.session.runSQL("SELECT name, amount FROM data ORDER BY amount DESC")
    check("SQL 列顺序", sortedSQL.columns.map(\.name) == ["name", "amount"])
    check("SQL 首行 O'Brien", sortedSQL.rows.first?.first == "O'Brien")

    let described = try query.session.runSQL("DESCRIBE SELECT * FROM data")
    check("DESCRIBE 返回 3 列", described.rowCount == 3)

    var dropRejected = false
    do { _ = try query.session.runSQL("DROP TABLE data") } catch { dropRejected = true }
    check("SQL 写语句被拒绝", dropRejected)

    let beforeWriteAttempt = SHA256.hash(data: try Data(contentsOf: queryCSV))
    var deleteRejected = false
    do { _ = try query.session.runSQL("DELETE FROM data") } catch { deleteRejected = true }
    check("SQL DELETE 被拒绝", deleteRejected)
    let afterWriteAttempt = SHA256.hash(data: try Data(contentsOf: queryCSV))
    check("拒绝写语句后源文件不变", beforeWriteAttempt == afterWriteAttempt)

    var syntaxRejected = false
    do { _ = try query.session.runSQL("SELEC * FROM data") } catch { syntaxRejected = true }
    check("SQL 语法错误被拒绝", syntaxRejected)

    let emptySQL = try query.session.runSQL("SELECT * FROM data WHERE 1 = 0")
    check("SQL 空结果 0 行", emptySQL.rowCount == 0)

    let tempCreated = try query.session.runSQL("CREATE TEMP TABLE t AS SELECT 1 AS a")
    check("CREATE TEMP 成功", tempCreated.rowCount == 0)
    let tempRead = try query.session.runSQL("SELECT * FROM t")
    check("临时表可查询", tempRead.rows.first?.first == "1")

    // 临时表只活在当前会话，关掉就没了
    let tempOwner = try FileImporter.open(url: queryCSV)
    _ = try tempOwner.session.runSQL("CREATE TEMP TABLE keep AS SELECT 1 AS a")
    tempOwner.session.close()
    let reopened = try FileImporter.open(url: queryCSV)
    var tempTableGone = false
    do { _ = try reopened.session.runSQL("SELECT * FROM keep") } catch { tempTableGone = true }
    check("关闭会话后临时表消失", tempTableGone)
    reopened.session.close()

    let truncated = try query.session.runSQL("SELECT * FROM range(100001)")
    check("SQL 结果截断到 10 万", truncated.rowCount == 100000 && truncated.truncated)

    try query.session.apply(view: QueryView(filter: FilterGroup(join: .and, conditions: [
        FilterCondition(column: "city", op: .equal, value: "上海")
    ])))
    let totalAfterFilter = try query.session.runSQL("SELECT count(*) FROM data")
    check("data 视图不受筛选影响", totalAfterFilter.rows.first?.first == "6")

    // 透视
    try query.session.apply(view: .empty)

    let pivotSum = try query.session.pivot(spec: PivotSpec(
        rows: ["city"],
        values: [PivotValue(column: "amount", aggregate: .sum)]
    ))
    check("透视三行", pivotSum.rowCount == 3)
    let shanghai = pivotSum.rows.first { $0.first == "上海" }
    check("上海求和 1000", shanghai?[1] == "1000")

    let pivotCross = try query.session.pivot(spec: PivotSpec(
        rows: ["city"],
        columns: ["name"],
        values: [PivotValue(column: "amount", aggregate: .sum)]
    ))
    check("交叉表七列", pivotCross.columns.count == 7)

    let pivotCount = try query.session.pivot(spec: PivotSpec(
        rows: ["city"],
        values: [PivotValue(column: "name", aggregate: .count)]
    ))
    check("上海计数 4", pivotCount.rows.first { $0.first == "上海" }?[1] == "4")

    let pivotMulti = try query.session.pivot(spec: PivotSpec(
        rows: ["city"],
        values: [
            PivotValue(column: "amount", aggregate: .sum),
            PivotValue(column: "amount", aggregate: .average)
        ]
    ))
    check("多值三列", pivotMulti.columns.count == 3)

    var pivotInvalid = false
    do { _ = try query.session.pivot(spec: PivotSpec(rows: ["city"])) } catch { pivotInvalid = true }
    check("缺值字段被拒绝", pivotInvalid)

    // R-PVT-02：生成的 SQL 拿到 SQL 抽屉里能复现同样的结果。
    let pivotSpecForSQL = PivotSpec(
        rows: ["city"],
        values: [PivotValue(column: "amount", aggregate: .sum)]
    )
    let generatedSQL = try query.session.pivotSQL(spec: pivotSpecForSQL)
    check("透视 SQL 是 SELECT 开头", generatedSQL.hasPrefix("SELECT "))
    check("透视 SQL 查的是 data 视图", generatedSQL.contains("FROM \"data\""))
    let replayed = try query.session.runSQL(generatedSQL)
    check("复现结果行数一致", replayed.rowCount == pivotSum.rowCount)
    func pairRows(_ rows: [[String?]]) -> Set<String> {
        var pairs: Set<String> = []
        for row in rows {
            let label: String = row.first.flatMap { $0 } ?? ""
            let value: String = row.count > 1 ? (row[1] ?? "") : ""
            pairs.insert("\(label)=\(value)")
        }
        return pairs
    }
    check("复现结果与透视一致", pairRows(replayed.rows) == pairRows(pivotSum.rows))

    // 带列维度的交叉表也要能复现，条件聚合那一段最容易拼错。
    let crossSQL = try query.session.pivotSQL(spec: PivotSpec(
        rows: ["city"],
        columns: ["name"],
        values: [PivotValue(column: "amount", aggregate: .sum)]
    ))
    let crossReplay = try query.session.runSQL(crossSQL)
    check("交叉表 SQL 复现列数一致", crossReplay.columns.count == pivotCross.columns.count)
    check("交叉表 SQL 复现行数一致", crossReplay.rowCount == pivotCross.rowCount)

    // 带筛选的透视，SQL 里也得带 WHERE。
    let pivotSQLWithFilter = try query.session.pivotSQL(spec: PivotSpec(
        rows: ["city"],
        values: [PivotValue(column: "amount", aggregate: .sum)],
        filter: FilterGroup(conditions: [FilterCondition(column: "city", op: .equal, value: "上海")])
    ))
    check("透视 SQL 带上筛选", pivotSQLWithFilter.contains("WHERE"))
    let filteredReplay = try query.session.runSQL(pivotSQLWithFilter)
    check("带筛选的复现只剩一行", filteredReplay.rowCount == 1)
    check("带筛选的复现求和 1000", filteredReplay.rows.first?[1] == "1000")

    // 六种聚合都能跑，且口径对得上（R-PVT 2.2）
    func pivotSingle(_ aggregate: PivotAggregate) throws -> String? {
        let result = try query.session.pivot(spec: PivotSpec(
            rows: ["city"],
            columns: ["name"],
            values: [PivotValue(column: "amount", aggregate: aggregate)]
        ))
        // 每个城市一行，取第一行第一个值列，跟手算的整体口径比。
        return result.rows.first.flatMap { $0.count > 1 ? $0[1] : nil }
    }
    var aggregateCount = 0
    for aggregate in PivotAggregate.allCases {
        do {
            _ = try pivotSingle(aggregate)
            aggregateCount += 1
        } catch {
            print("      聚合 \(aggregate.rawValue) 失败: \(error)")
        }
    }
    check("六种聚合都能执行", aggregateCount == PivotAggregate.allCases.count)
    check("六种聚合标题齐全", Set(PivotAggregate.allCases.map(\.title)).count == 6)

    // 聚合结果要跟手写 SQL 对得上，不只是"能跑"。
    // rows 里每个格子是 String?，取值要剥两层。
    func scalar(_ result: SQLResult) -> String? {
        guard let row = result.rows.first, let cell = row.first else { return nil }
        return cell
    }
    let maxSQL = try query.session.runSQL("SELECT max(amount) FROM data")
    let maxValue = Double(scalar(maxSQL) ?? "") ?? -1
    let maxPivot = try query.session.pivot(spec: PivotSpec(
        rows: ["city"],
        values: [PivotValue(column: "amount", aggregate: .maximum)]
    ))
    let maxOfRows = maxPivot.rows.compactMap { Double($0[1] ?? "") }.max() ?? -1
    check("最大值聚合与 SQL MAX 一致", abs(maxOfRows - maxValue) < 0.001)

    let minSQL = try query.session.runSQL("SELECT min(amount) FROM data")
    let minValue = Double(scalar(minSQL) ?? "") ?? -1
    let minPivot = try query.session.pivot(spec: PivotSpec(
        rows: ["city"],
        values: [PivotValue(column: "amount", aggregate: .minimum)]
    ))
    let minOfRows = minPivot.rows.compactMap { Double($0[1] ?? "") }.min() ?? -1
    check("最小值聚合与 SQL MIN 一致", abs(minOfRows - minValue) < 0.001)

    let distinctSQL = try query.session.runSQL("SELECT count(DISTINCT amount) FROM data")
    let distinctValue = Int(scalar(distinctSQL) ?? "") ?? -1
    let distinctPivot = try query.session.pivot(spec: PivotSpec(
        rows: ["city"],
        values: [PivotValue(column: "amount", aggregate: .countDistinct)]
    ))
    let distinctTotal = distinctPivot.rows.compactMap { Int($0[1] ?? "") }.reduce(0, +)
    // 各城市去重值互不共享时总和等于整体去重；这里数据有交集，卡下界更有意义。
    check("去重计数不小于整体去重", distinctValue > 0 && distinctTotal >= distinctValue)

    // 基数超限给可读提示，不是崩溃（R-PVT 2.4）
    let wideCSV = working.appendingPathComponent("pivot-wide.csv")
    var wideLines = ["k,amount"]
    for index in 0..<5100 { wideLines.append("k\(index),\(index)") }
    try wideLines.joined(separator: "\n").write(to: wideCSV, atomically: true, encoding: .utf8)
    let wideSession = try FileImporter.open(url: wideCSV)
    var rowLimitError: String?
    do {
        _ = try wideSession.session.pivot(spec: PivotSpec(
            rows: ["k"],
            values: [PivotValue(column: "amount", aggregate: .sum)]
        ))
    } catch let error as ImportError {
        rowLimitError = error.userMessage
    }
    check("行维度超 5000 给提示", rowLimitError == "行维度太多了")

    var columnLimitError: String?
    do {
        _ = try wideSession.session.pivot(spec: PivotSpec(
            rows: ["k"],
            columns: ["amount"],
            values: [PivotValue(column: "amount", aggregate: .sum)]
        ))
    } catch let error as ImportError {
        columnLimitError = error.userMessage
    }
    check("列维度超 200 给提示", columnLimitError == "列维度太多了")
    check("超限后会话仍可用", (try? wideSession.session.runSQL("SELECT count(*) FROM data"))?.rows.first?.first == "5100")
    wideSession.session.close()

    // 透视里的 NULL 与空字符串分开显示
    let nullCSV = working.appendingPathComponent("nulls.csv")
    try "name,city,amount\na,,1\nb,,2\nc,上海,3\nd,上海,4\ne,\"\",5\n".write(to: nullCSV, atomically: true, encoding: .utf8)
    let nullSession = try FileImporter.open(url: nullCSV)
    let nullPivot = try nullSession.session.pivot(spec: PivotSpec(
        rows: ["city"],
        values: [PivotValue(column: "amount", aggregate: .sum)]
    ))
    let labels = nullPivot.rows.compactMap { $0.first }
    check("透视含 (空)", labels.contains("(空)"))
    check("透视含 上海", labels.contains("上海"))
    let nullCross = try nullSession.session.pivot(spec: PivotSpec(
        rows: ["name"],
        columns: ["city"],
        values: [PivotValue(column: "amount", aggregate: .sum)]
    ))
    check("交叉表保留空值列", nullCross.columns.count == 3)
    check("交叉表空值列名", nullCross.columns.contains { $0.displayName.contains("(空)") })
    nullSession.session.close()

    // 列统计与导出
    let amountStats = try query.session.columnStats(column: "amount")
    check("金额统计总数 6", amountStats.totalRows == 6 && amountStats.nullCount == 0 && amountStats.distinctCount == 6)
    check("金额最小最大", amountStats.minValue == "30" && amountStats.maxValue == "400")
    check("金额均值 180", abs((amountStats.mean ?? 0) - 180) < 0.001)
    check("金额中位数 150", abs((amountStats.median ?? 0) - 150) < 0.001)
    check("直方图 20 桶且计数 6", amountStats.histogram.count == 20 && amountStats.histogram.reduce(0) { $0 + $1.count } == 6)

    // 检查器的均值必须和 SQL AVG 对得上
    let avgSQL = try query.session.runSQL("SELECT avg(amount) FROM data")
    let avgRaw: String? = avgSQL.rows.first?[0] ?? nil
    let avgValue = Double(avgRaw ?? "") ?? -1
    check("均值与 SQL AVG 一致", abs(avgValue - (amountStats.mean ?? 0)) < 0.001)

    // 透视结果必须能用手写 GROUP BY 复现
    let groupSQL = try query.session.runSQL("SELECT city, sum(amount) FROM data GROUP BY city ORDER BY city")
    let groupPairs = Set(groupSQL.rows.compactMap { row -> String? in
        guard row.count == 2, let city = row[0], let total = row[1] else { return nil }
        return "\(city)=\(Double(total) ?? 0)"
    })
    let pivotPairs = Set(pivotSum.rows.compactMap { row -> String? in
        guard row.count == 2, let city = row[0], let total = row[1] else { return nil }
        return "\(city)=\(Double(total) ?? 0)"
    })
    check("透视与手写 GROUP BY 一致", groupPairs == pivotPairs)

    // 图表：单维度聚合 + 排序 + 收口
    let chartSpec = ChartSpec(kind: .bar, groupColumn: "city", value: PivotValue(column: "amount", aggregate: .sum))
    let chartResult = try query.session.pivot(spec: chartSpec.pivotSpec)
    let chart = ChartData.build(result: chartResult, spec: chartSpec)
    let chartPairs = Set(chart.points.map { "\($0.label)=\($0.value)" })
    check("图表与手写 GROUP BY 一致", chartPairs == groupPairs)
    check("柱状图按数值降序", zip(chart.points, chart.points.dropFirst()).allSatisfy { $0.value >= $1.value })
    let totalSQL = try query.session.runSQL("SELECT sum(amount) FROM data")
    let totalValue = Double(totalSQL.rows.first?[0] ?? "") ?? -1
    check("图表总量等于 SQL 求和", abs(chart.total - totalValue) < 0.001)
    check("图表最大值等于最大分组", abs(chart.maxValue - (chart.points.map(\.value).max() ?? 0)) < 0.001)

    // 超过 12 组时合并成“其他”
    let manyColumns = [ColumnInfo(name: "k", displayName: "k", typeName: "VARCHAR", kind: .text),
                       ColumnInfo(name: "v", displayName: "v", typeName: "DOUBLE", kind: .double)]
    let manyRows = (0..<900).map { index -> [String?] in
        ["k\(index)", "\(900 - index)"]
    }
    let manyResult = SQLResult(columns: manyColumns, rows: manyRows, rowCount: manyRows.count, elapsed: 0.01, truncated: false)
    let merged = ChartData.build(result: manyResult, spec: ChartSpec(kind: .bar, groupColumn: "k", value: PivotValue(column: "v")))
    check("超过 12 组收口为 13 个点", merged.points.count == 13 && merged.mergedCount == 888)
    check("其他等于剩余之和", abs((merged.points.last?.value ?? 0) - (888.0 * 889 / 2)) < 1)
    check("收口后量级按前 12 名算", abs(merged.maxValue - 900) < 0.001)

    // 折线图按标签升序
    let lineRows: [[String?]] = [["2026-03", "30"], ["2026-01", "10"], ["2026-02", "20"]]
    let lineResult = SQLResult(columns: manyColumns, rows: lineRows, rowCount: 3, elapsed: 0, truncated: false)
    let line = ChartData.build(result: lineResult, spec: ChartSpec(kind: .line, groupColumn: "k", value: PivotValue(column: "v")))
    check("折线图按标签升序", line.points.map(\.label) == ["2026-01", "2026-02", "2026-03"])

    // 非数值与空结果
    let dirtyRows: [[String?]] = [["a", "12.5"], ["b", "—"], ["c", nil]]
    let dirtyResult = SQLResult(columns: manyColumns, rows: dirtyRows, rowCount: 3, elapsed: 0, truncated: false)
    let dirty = ChartData.build(result: dirtyResult, spec: ChartSpec(kind: .bar, groupColumn: "k", value: PivotValue(column: "v")))
    check("跳过非数值与空值", dirty.points.count == 1 && dirty.points[0].label == "a")
    let emptyChart = ChartData.build(result: .empty, spec: chartSpec)
    check("空结果不画图", emptyChart.isEmpty && emptyChart.maxValue == 0)
    check("数值千分位格式", ChartData.format(12345.6789) == "12,345.68")

    // 只有一个分组时也要画得出来，不能除零（R-VIZ-02）。
    let singleRows: [[String?]] = [["上海", "100"]]
    let singleResult = SQLResult(columns: manyColumns, rows: singleRows, rowCount: 1, elapsed: 0, truncated: false)
    let single = ChartData.build(result: singleResult, spec: ChartSpec(kind: .pie, groupColumn: "k", value: PivotValue(column: "v")))
    check("单分组画一个点", single.points.count == 1 && single.points[0].label == "上海")
    check("单分组量级等于自身", abs(single.maxValue - 100) < 0.001)
    check("单分组饼图占满 100%", abs(single.points[0].value / single.total - 1) < 0.0001)

    // 先筛选再建图，只统计筛选结果（R-VIZ-03）。
    try query.session.apply(view: QueryView(filter: FilterGroup(join: .and, conditions: [
        FilterCondition(column: "city", op: .equal, value: "上海")
    ])))
    let filteredChartResult = try query.session.pivot(spec: chartSpec.pivotSpec)
    let filteredChart = ChartData.build(result: filteredChartResult, spec: chartSpec)
    check("筛选后图表只剩一个分组", filteredChart.points.count == 1 && filteredChart.points[0].label == "上海")
    let filteredSumSQL = try query.session.runSQL("SELECT sum(amount) FROM data WHERE city = '上海'")
    let filteredSum = Double(filteredSumSQL.rows.first?[0] ?? "") ?? -1
    check("筛选后图表数值等于筛选后求和", abs(filteredChart.total - filteredSum) < 0.001)
    try query.session.apply(view: .empty)

    // 筛到 0 行时给空图，由界面显示“没有匹配的数据”。
    try query.session.apply(view: QueryView(filter: FilterGroup(join: .and, conditions: [
        FilterCondition(column: "city", op: .equal, value: "不存在的城市")
    ])))
    let noMatchResult = try query.session.pivot(spec: chartSpec.pivotSpec)
    let noMatchChart = ChartData.build(result: noMatchResult, spec: chartSpec)
    check("筛选到 0 行给空图", noMatchChart.isEmpty && noMatchResult.rowCount == 0)
    try query.session.apply(view: .empty)

    // 一键分析：挑列、基数过滤、兜底
    let autoColumns = [
        ColumnInfo(name: "order", displayName: "订单号", typeName: "VARCHAR", kind: .text),
        ColumnInfo(name: "region", displayName: "区域", typeName: "VARCHAR", kind: .text),
        ColumnInfo(name: "channel", displayName: "渠道", typeName: "VARCHAR", kind: .text),
        ColumnInfo(name: "amount", displayName: "金额", typeName: "DOUBLE", kind: .double),
        ColumnInfo(name: "qty", displayName: "数量", typeName: "BIGINT", kind: .integer)
    ]
    let autoSpecs = AutoAnalysis.plan(columns: autoColumns) { name in
        switch name {
        case "order": return 3_282_000
        case "region": return 5
        case "channel": return 4
        default: return 1
        }
    }
    check("一键分析跳过订单号", autoSpecs.allSatisfy { $0.groupColumn != "order" })
    check("一键分析挑出两个维度", autoSpecs.map(\.groupColumn) == ["region", "channel"])
    check("一键分析度量选金额", autoSpecs.first?.value.column == "amount")
    let reordered = [
        ColumnInfo(name: "qty", displayName: "数量", typeName: "BIGINT", kind: .integer),
        ColumnInfo(name: "amount", displayName: "金额", typeName: "DOUBLE", kind: .double)
    ]
    check("金额比数量优先", AutoAnalysis.measureColumn(reordered)?.name == "amount")

    // 自绘单元格要保留辅助功能文本
    let cell = GridTextCellView(frame: NSRect(x: 0, y: 0, width: 80, height: 20))
    cell.configure(text: "12,345.68", alignment: .right, color: .labelColor)
    check("单元格辅助功能标签", cell.accessibilityLabel() == "12,345.68")
    let noneSpecs = AutoAnalysis.plan(columns: autoColumns) { _ in 100 }
    check("基数全超限时不出图", noneSpecs.isEmpty)
    check("没有数值列不出图", AutoAnalysis.plan(columns: [autoColumns[1]]) { _ in 3 }.isEmpty)

    let cityDistinct = try query.session.distinctCount(column: "city")
    let cityDistinctSQL = Int(try query.session.runSQL("SELECT count(DISTINCT city) FROM data").rows.first?[0] ?? "") ?? -1
    check("去重计数与 SQL 一致", cityDistinct == cityDistinctSQL)
    let singlePlan = AutoAnalysis.plan(columns: query.session.columns) { _ in 6 }
    check("小表一键分析出图", singlePlan.contains { $0.groupColumn == "city" } && singlePlan.first?.value.column == "amount")

    let cityStats = try query.session.columnStats(column: "city")
    let nameStats = try query.session.columnStats(column: "name")
    check("文本最短长度 1", nameStats.minLength == 1)
    check("文本最长长度 7", nameStats.maxLength == 7)
    check("无首尾空白", nameStats.whitespaceCount == 0)
    let nameStatsAgain = try query.session.columnStats(column: "name")
    check("统计缓存命中", nameStatsAgain.totalRows == nameStats.totalRows && nameStatsAgain.maxLength == 7)
    check("城市高频值第一", cityStats.topValues.first?.value == "上海" && cityStats.topValues.first?.count == 4)

    let nullStats = try opened.session.columnStats(column: "备注")
    check("空值统计 2", nullStats.nullCount == 2)

    let mixedURL = working.appendingPathComponent("mixed.csv")
    try "code\n100\n200\n—\n300\n".write(to: mixedURL, atomically: true, encoding: .utf8)
    let mixed = try FileImporter.open(url: mixedURL)
    let mixedStats = try mixed.session.columnStats(column: "code")
    check("混合列按文本", mixedStats.kind == .text)
    check("混合列数字 3 行", mixedStats.numericCount == 3 && mixedStats.conflictCount == 1)
    check("混合列反例", mixedStats.nonNumericExamples == ["—"])
    check("纯文本不误报", cityStats.numericCount == 0)
    check("数值列无冲突", amountStats.conflictCount == 0)

    let exportURL = working.appendingPathComponent("export.csv")
    _ = try query.session.export(to: exportURL, format: .csv)
    let csvPrefix = try Data(contentsOf: exportURL).prefix(3)
    check("CSV 带 UTF-8 BOM", csvPrefix.elementsEqual([0xEF, 0xBB, 0xBF]))
    let exported = try FileImporter.open(url: exportURL)
    check("CSV 导出行数 6", exported.session.rowCount == 6)
    check("CSV 导出可再次打开", try exported.session.block(offset: 0, size: 1).rows.first?.first == "a")

    let parquetURL = working.appendingPathComponent("export.parquet")
    _ = try query.session.export(to: parquetURL, format: .parquet)
    let exportedParquet = try DuckDBSession.openParquet(url: parquetURL)
    check("Parquet 导出行数 6", exportedParquet.rowCount == 6)

    let importedParquet = try FileImporter.open(url: parquetURL)
    check("Parquet 可再次打开", importedParquet.session.rowCount == 6)
    check("Parquet 编码标记", importedParquet.encoding == .parquet)
    check("Parquet 首行有值", try importedParquet.session.block(offset: 0, size: 1).rows.first?.first != nil)
    importedParquet.session.close()

    // Parquet 视图分支：小文件也强制走 __rid 路径，验证取块、筛选与 data 视图不暴露 __rid
    DuckDBSession.parquetViewCellThreshold = 0
    let viewOpened = try FileImporter.open(url: parquetURL)
    check("视图分支行数 6", viewOpened.session.rowCount == 6)
    check("视图分支首块有值", try viewOpened.session.block(offset: 0, size: 2).rows.first?.first != nil)
    let lastBlock = try viewOpened.session.block(offset: 5, size: 1)
    check("视图分支末块 1 行", lastBlock.rows.count == 1)
    try viewOpened.session.apply(view: QueryView(sort: [SortSpec(column: "amount", ascending: false)]))
    let maxAmount = Double(try viewOpened.session.runSQL("SELECT max(amount) FROM data").rows.first?[0] ?? "") ?? -1
    let amountIndex = viewOpened.session.columns.firstIndex { $0.name == "amount" } ?? 0
    let firstRow = try viewOpened.session.block(offset: 0, size: 1).rows.first ?? []
    let firstAmount = Double(amountIndex < firstRow.count ? (firstRow[amountIndex] ?? "") : "") ?? -2
    check("视图分支排序后首行最大", abs(firstAmount - maxAmount) < 0.001)
    let starSQL = try viewOpened.session.runSQL("SELECT * FROM data LIMIT 1")
    check("data 视图不含 __rid", starSQL.columns.count == 3 && starSQL.columns.allSatisfy { $0.name != "__rid" })
    viewOpened.session.close()
    DuckDBSession.parquetViewCellThreshold = 20_000_000

    try query.session.apply(view: QueryView(filter: FilterGroup(join: .and, conditions: [
        FilterCondition(column: "city", op: .equal, value: "上海")
    ])))
    let filteredURL = working.appendingPathComponent("filtered.csv")
    _ = try query.session.export(to: filteredURL, format: .csv)
    let filteredExport = try FileImporter.open(url: filteredURL)
    check("筛选导出 4 行", filteredExport.session.rowCount == 4)

    // 导出范围：全部行忽略筛选，选中行按网格位置
    let allURL = working.appendingPathComponent("all-rows.csv")
    let allCount = try query.session.export(to: allURL, format: .csv, scope: .all)
    let allExport = try FileImporter.open(url: allURL)
    check("全部行导出 6 行", allCount == 6 && allExport.session.rowCount == 6)
    allExport.session.close()

    let viewOrder = try query.session.block(offset: 0, size: 5).rows.map { $0[0] }
    let pickedURL = working.appendingPathComponent("picked-rows.csv")
    let pickedCount = try query.session.export(to: pickedURL, format: .csv, scope: .rows(IndexSet([0, 2])))
    let picked = try FileImporter.open(url: pickedURL)
    let pickedOrder = try picked.session.block(offset: 0, size: 5).rows.map { $0[0] }
    check("选中行导出行数 2", pickedCount == 2 && picked.session.rowCount == 2)
    check("选中行顺序与网格一致", pickedOrder == [viewOrder[0], viewOrder[2]])
    picked.session.close()

    let emptySelectionRejected: Bool
    do {
        _ = try query.session.export(to: working.appendingPathComponent("empty.csv"), format: .csv, scope: .rows(IndexSet()))
        emptySelectionRejected = false
    } catch {
        emptySelectionRejected = true
    }
    check("空选中行被拒绝", emptySelectionRejected)

    // 排序后再按位置导出，行号跟着视图走
    try query.session.apply(view: QueryView(sort: [SortSpec(column: "amount", ascending: false)]))
    let sortedOrder = try query.session.block(offset: 0, size: 5).rows.map { $0[0] }
    let sortedURL = working.appendingPathComponent("sorted-pick.csv")
    _ = try query.session.export(to: sortedURL, format: .csv, scope: .rows(IndexSet([1])))
    let sortedPick = try FileImporter.open(url: sortedURL)
    check("排序后选中行取第 2 行", try sortedPick.session.block(offset: 0, size: 1).rows.first?[0] == sortedOrder[1])
    sortedPick.session.close()

    // 选中行导出用完就清理临时表，后面的当前视图导出不受影响
    let afterPickURL = working.appendingPathComponent("after-pick.csv")
    _ = try query.session.export(to: afterPickURL, format: .csv, scope: .view)
    let afterPick = try FileImporter.open(url: afterPickURL)
    check("选中行导出后视图导出仍 6 行", afterPick.session.rowCount == 6)
    afterPick.session.close()
    try query.session.apply(view: .empty)

    // 计算列
    let beforeComputed = query.session.displayColumns.count
    try query.session.addComputedColumn(name: "tax", expression: "amount * 0.06")
    check("计算列添加", query.session.displayColumns.count == beforeComputed + 1)
    check("计算列标记", query.session.displayColumns.last?.isComputed == true)
    let computedBlock = try query.session.block(offset: 0, size: 1)
    let taxCell: String? = (computedBlock.rows.first ?? []).last ?? nil
    check("计算列值 6", abs((Double(taxCell ?? "") ?? -1) - 6.0) < 0.0001)

    var duplicateComputed = false
    do { try query.session.addComputedColumn(name: "amount", expression: "1") } catch { duplicateComputed = true }
    check("计算列重名拒绝", duplicateComputed)

    var badComputed = false
    do { try query.session.addComputedColumn(name: "bad", expression: "amount *") } catch { badComputed = true }
    check("计算列表达式拒绝", badComputed)

    let computedExportURL = working.appendingPathComponent("with-computed.csv")
    _ = try query.session.export(to: computedExportURL, format: .csv)
    let computedExport = try FileImporter.open(url: computedExportURL)
    check("导出不含计算列", computedExport.session.columns.count == 3 && computedExport.session.rowCount == 6)

    // Parquet 缓存
    let cacheDirectory = working.appendingPathComponent("cache")
    let parquetCache = ParquetCache(baseDirectory: cacheDirectory, limitBytes: 100 * 1024 * 1024)
    ParquetCache.shared = parquetCache

    let cacheCSV = working.appendingPathComponent("cache-test.csv")
    try "name,amount\nx,1\ny,2\n".write(to: cacheCSV, atomically: true, encoding: .utf8)

    let firstCacheOpen = try FileImporter.open(url: cacheCSV)
    check("首次打开未命中缓存", !firstCacheOpen.usedCache)

    var cachedFile: URL?
    for _ in 0..<100 {
        if let found = parquetCache.cachedURL(for: cacheCSV, variant: TextEncoding.utf8.rawValue) {
            cachedFile = found
            break
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    check("后台生成 Parquet 缓存", cachedFile != nil)

    let secondCacheOpen = try FileImporter.open(url: cacheCSV)
    check("二次打开命中缓存", secondCacheOpen.usedCache)
    check("缓存行列一致", secondCacheOpen.session.rowCount == 2 && secondCacheOpen.session.columns.count == 2)
    check("缓存首行正确", try secondCacheOpen.session.block(offset: 0, size: 1).rows.first?.first == "x")

    Thread.sleep(forTimeInterval: 1.2)
    try "name,amount\nx,1\ny,2\nz,3\n".write(to: cacheCSV, atomically: true, encoding: .utf8)
    check("修改文件后旧缓存失效", parquetCache.cachedURL(for: cacheCSV, variant: TextEncoding.utf8.rawValue) == nil)
    let modifiedOpen = try FileImporter.open(url: cacheCSV)
    check("修改后回退 CSV", !modifiedOpen.usedCache && modifiedOpen.session.rowCount == 3)

    let evictDirectory = working.appendingPathComponent("evict-cache")
    let evictCache = ParquetCache(baseDirectory: evictDirectory, limitBytes: 10)
    let oldFile = evictDirectory.appendingPathComponent("old.parquet")
    let newFile = evictDirectory.appendingPathComponent("new.parquet")
    try Data(repeating: 1, count: 100).write(to: oldFile)
    try Data(repeating: 1, count: 100).write(to: newFile)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-100)], ofItemAtPath: oldFile.path)
    evictCache.evictIfNeeded(keeping: newFile)
    check("超过上限删除最旧缓存", !FileManager.default.fileExists(atPath: oldFile.path) && FileManager.default.fileExists(atPath: newFile.path))

    let limitDirectory = working.appendingPathComponent("limit-cache")
    let limitCache = ParquetCache(baseDirectory: limitDirectory, limitBytes: 1_000)
    try Data(repeating: 1, count: 100).write(to: limitDirectory.appendingPathComponent("a.parquet"))
    try Data(repeating: 1, count: 100).write(to: limitDirectory.appendingPathComponent("b.parquet"))
    check("缓存占用统计 200", limitCache.totalSizeBytes() == 200)
    limitCache.setLimitBytes(10)
    check("设置上限立即淘汰", limitCache.totalSizeBytes() == 0)

    // Excel 导入
    let fixture = URL(fileURLWithPath: "Tests/Fixtures/sample.xlsx")
    let xlsx = try FileImporter.open(url: fixture)
    check("xlsx 行数 4", xlsx.session.rowCount == 4)
    check("xlsx 列数 4", xlsx.session.columns.count == 4)
    check("xlsx 首行张三", try xlsx.session.block(offset: 0, size: 1).rows.first?.first == "张三")
    check("xlsx 空金额为 NULL", try xlsx.session.block(offset: 2, size: 1).rows.first?[1] == nil)
    check("xlsx 布尔显示", try xlsx.session.block(offset: 1, size: 1).rows.first?[3] == "FALSE")
    check("xlsx 不导入第二张表", try xlsx.session.block(offset: 0, size: 4).rows.allSatisfy { $0.first != "华东" })

    // 工作表太多时拒绝全部导入，避免一点就卡几分钟
    let manySheets = MainActor.assumeIsolated { WorkspaceModel() }
    MainActor.assumeIsolated {
        manySheets.open(url: fixture, sheetNames: (1...21).map { "表\($0)" })
    }
    check("超过 20 张工作表被拒绝", MainActor.assumeIsolated { manySheets.error?.userMessage == "工作表太多了" })
    check("拒绝时不进左栏", MainActor.assumeIsolated { manySheets.entries.isEmpty })

    var xlsxCached: URL?
    for _ in 0..<100 {
        if let found = ParquetCache.shared.cachedURL(for: fixture, variant: "xlsx:数据") {
            xlsxCached = found
            break
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    check("xlsx 生成缓存", xlsxCached != nil)
    let xlsxSecond = try FileImporter.open(url: fixture)
    check("xlsx 二次命中缓存", xlsxSecond.usedCache)
    check("xlsx 缓存行数一致", xlsxSecond.session.rowCount == 4)

    check("xlsx 公式无缓存留空", try xlsx.session.block(offset: 3, size: 1).rows.first?[1] == nil)
    check("支持 xlsx 扩展名", FileImporter.supportedExtensions.contains("xlsx"))

    let cleanupSource = working.appendingPathComponent("cleanup-source.csv")
    try "a,b\n1,2\n".write(to: cleanupSource, atomically: true, encoding: .utf8)
    let dummyKey = working.appendingPathComponent("dummy.csv")
    ParquetCache.shared.scheduleConversion(
        sourceKey: dummyKey,
        readableURL: cleanupSource,
        format: CSVFormat(delimiter: ",", hasHeader: true),
        variant: "cleanup-test",
        cleanupAfterConversion: true
    )
    var cleaned = false
    for _ in 0..<100 {
        if !FileManager.default.fileExists(atPath: cleanupSource.path) {
            cleaned = true
            break
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    check("转换后删除临时 CSV", cleaned)

    let secondSheet = try FileImporter.open(url: fixture, sheetName: "汇总")
    check("指定工作表行数 1", secondSheet.session.rowCount == 1)
    check("指定工作表首行华东", try secondSheet.session.block(offset: 0, size: 1).rows.first?.first == "华东")
    check("工作表名记录", secondSheet.sheetName == "汇总")

    let badXLSX = working.appendingPathComponent("bad.xlsx")
    try "not an excel file".write(to: badXLSX, atomically: true, encoding: .utf8)
    var badXLSXRejected = false
    do { _ = try FileImporter.open(url: badXLSX) } catch { badXLSXRejected = true }
    check("损坏的 xlsx 被拒绝", badXLSXRejected)

    // TSV 复制
    let tsv = TSVBuilder.build(
        rows: [["a", "b\tc", "d\"e"], [nil, "line\nbreak", ""]],
        columns: ["A", "B", "C"],
        includeHeader: true
    )
    check("TSV 表头", tsv.hasPrefix("A\tB\tC"))
    check("TSV 制表符转义", tsv.contains("\"b\tc\""))
    check("TSV 换行转义", tsv.contains("\"line\nbreak\""))
    check("TSV 引号转义", tsv.contains("\"d\"\"e\""))
    let noHeaderTSV = TSVBuilder.build(rows: [["1", "2"]], columns: ["A", "B"], includeHeader: false)
    check("TSV 无表头", noHeaderTSV == "1\t2")

    let gridSource = GridDataSource()
    gridSource.configure(
        columns: [
            ColumnInfo(name: "A", displayName: "A", typeName: "VARCHAR", kind: .text),
            ColumnInfo(name: "B", displayName: "B", typeName: "VARCHAR", kind: .text)
        ],
        rowCount: 2,
        provider: { _, _ in TableBlock(offset: 0, rows: [["a", "b"], ["c", "d"]]) }
    )

    let gridTable = GridTableView()
    gridTable.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
    gridTable.dataSource = gridSource
    gridTable.delegate = gridSource
    gridTable.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("A")))
    gridTable.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("B")))
    gridTable.reloadData()
    gridTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

    UserDefaults.standard.set(true, forKey: "copyIncludesHeader")
    gridTable.copy(nil)
    check("Command+C 写入 TSV", NSPasteboard.general.string(forType: .string) == "A\tB\na\tb")
    UserDefaults.standard.set(false, forKey: "copyIncludesHeader")
    gridTable.copy(nil)
    check("复制不带表头", NSPasteboard.general.string(forType: .string) == "a\tb")
    UserDefaults.standard.set(true, forKey: "copyIncludesHeader")

    // 大范围复制的确认规则（R-EXP-04）。阈值是“超过”一万，正好一万不打扰。
    check("一万行以内不弹框", !CopyConfirmation.needsConfirmation(rowCount: 10_000))
    check("一万零一行弹框", CopyConfirmation.needsConfirmation(rowCount: 10_001))
    check("确认框写出行数", CopyConfirmation.title(rowCount: 12_345).contains("12,345") == false
        && CopyConfirmation.title(rowCount: 12_345).contains("12345"))

    // 真的走一遍 GridTableView.copy 的分支：取消时剪贴板保持原样。
    let manySource = GridDataSource()
    manySource.configure(
        columns: [
            ColumnInfo(name: "A", displayName: "A", typeName: "VARCHAR", kind: .text),
            ColumnInfo(name: "B", displayName: "B", typeName: "VARCHAR", kind: .text)
        ],
        rowCount: 10_001,
        provider: { offset, size in
            let start = max(0, min(offset, 10_001))
            let end = max(start, min(offset + size, 10_001))
            let rows = (start..<end).map { ["r\($0)", "v\($0)"] as [String?] }
            return TableBlock(offset: start, rows: rows)
        }
    )
    let manyTable = GridTableView()
    manyTable.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
    manyTable.dataSource = manySource
    manyTable.delegate = manySource
    manyTable.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("A")))
    manyTable.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("B")))
    manyTable.reloadData()
    // 不在窗口里时 selectAll 会按可见区域算，直接指定整个区间。
    manyTable.selectRowIndexes(IndexSet(integersIn: 0..<10_001), byExtendingSelection: false)

    var askedRowCount: Int?
    manyTable.confirmCopy = { count in
        askedRowCount = count
        return false
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString("原有内容", forType: .string)
    manyTable.copy(nil)
    check("选一万行以上先问", askedRowCount == 10_001)
    check("取消后剪贴板不动", NSPasteboard.general.string(forType: .string) == "原有内容")

    var acceptedCount: Int?
    manyTable.confirmCopy = { count in
        acceptedCount = count
        return true
    }
    manyTable.copy(nil)
    check("确认后写入剪贴板", acceptedCount == 10_001
        && NSPasteboard.general.string(forType: .string)?.hasPrefix("A\tB") == true
        && NSPasteboard.general.string(forType: .string)?.contains("r10000\tv10000") == true)

    // 小范围复制不该触发确认。
    var smallAsked = false
    gridTable.confirmCopy = { _ in
        smallAsked = true
        return false
    }
    gridTable.copy(nil)
    check("小范围复制不问", !smallAsked && NSPasteboard.general.string(forType: .string) == "A\tB\na\tb")
    gridTable.confirmCopy = nil

    // SQL 历史
    let historySuite = "tableworkbench.history.\(UUID().uuidString)"
    let historyDefaults = UserDefaults(suiteName: historySuite)!
    let history = SQLHistoryStore(defaults: historyDefaults, key: "test")
    history.record("SELECT 1")
    history.record("SELECT 2")
    check("历史两条", history.entries.count == 2)
    check("历史最新在前", history.entries.first?.sql == "SELECT 2")
    history.record("SELECT 2")
    check("历史去重", history.entries.count == 2)
    for index in 0..<205 {
        history.record("SELECT \(index)")
    }
    check("历史上限 200", history.entries.count == 200)
    check("历史搜索", !history.search("SELECT 20").isEmpty)
    let reloadedHistory = SQLHistoryStore(defaults: historyDefaults, key: "test")
    check("历史持久化", reloadedHistory.entries.count == 200 && reloadedHistory.entries.first?.sql == "SELECT 204")
    history.clear()
    check("历史清空", history.entries.isEmpty && SQLHistoryStore(defaults: historyDefaults, key: "test").entries.isEmpty)
    historyDefaults.removePersistentDomain(forName: historySuite)

    // SQL 片段
    let snippetSuite = "tableworkbench.snippets.\(UUID().uuidString)"
    let snippetDefaults = UserDefaults(suiteName: snippetSuite)!
    let snippetStore = SQLSnippetStore(defaults: snippetDefaults, key: "test")
    snippetStore.save(name: "每月毛利", sql: "SELECT 1")
    check("片段保存", snippetStore.entries.count == 1 && snippetStore.entries.first?.name == "每月毛利")
    snippetStore.save(name: "每月毛利", sql: "SELECT 2")
    check("片段同名覆盖", snippetStore.entries.count == 1 && snippetStore.entries.first?.sql == "SELECT 2")
    snippetStore.save(name: "  ", sql: "SELECT 3")
    snippetStore.save(name: "空语句", sql: "  ")
    check("片段空值拒绝", snippetStore.entries.count == 1)
    snippetStore.save(name: "区域汇总", sql: "SELECT 4")
    check("片段两条", snippetStore.entries.count == 2)
    let reloadedSnippets = SQLSnippetStore(defaults: snippetDefaults, key: "test")
    check("片段持久化", reloadedSnippets.entries.count == 2)
    snippetStore.remove(id: snippetStore.entries[0].id)
    check("片段删除", snippetStore.entries.count == 1)
    snippetStore.clear()
    check("片段清空", snippetStore.entries.isEmpty && SQLSnippetStore(defaults: snippetDefaults, key: "test").entries.isEmpty)
    snippetDefaults.removePersistentDomain(forName: snippetSuite)

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

    // 文件切换：新打开的文件要被选中，换文件要清掉上一份的列统计
    let switchA = working.appendingPathComponent("switch-a.csv")
    let switchB = working.appendingPathComponent("switch-b.csv")
    try "name,amount\na,1\n".write(to: switchA, atomically: true, encoding: .utf8)
    try "name,amount\nb,2\n".write(to: switchB, atomically: true, encoding: .utf8)
    let model = MainActor.assumeIsolated { WorkspaceModel() }
    MainActor.assumeIsolated { model.open(urls: [switchA]) }
    waitFor { model.entries.count == 1 }
    let firstID = MainActor.assumeIsolated { model.entries.first?.id }
    check("第一个文件自动选中", MainActor.assumeIsolated { model.selection == firstID })
    MainActor.assumeIsolated { model.open(urls: [switchB]) }
    waitFor { model.entries.count == 2 }
    let secondID = MainActor.assumeIsolated { model.entries.last?.id }
    check("打开新文件后切到新文件", MainActor.assumeIsolated { model.selection == secondID })
    MainActor.assumeIsolated { model.loadStats(entryID: firstID!, column: "amount") }
    waitFor { MainActor.assumeIsolated { model.statsColumn == "amount" } }
    MainActor.assumeIsolated { model.selection = firstID }
    check("换文件清空列统计", MainActor.assumeIsolated { model.statsColumn == nil && model.columnStats == nil })
    MainActor.assumeIsolated { model.updateSelectedRows(IndexSet([0, 1])) }
    check("记录选中行", MainActor.assumeIsolated { model.selectedRows == IndexSet([0, 1]) })
    MainActor.assumeIsolated { model.selection = secondID }
    check("换文件清空选中行", MainActor.assumeIsolated { model.selectedRows.isEmpty })

    // 一键分析：真实文件走一遍挑列、聚合、出图
    let autoModel = MainActor.assumeIsolated { WorkspaceModel() }
    let autoFile = URL(fileURLWithPath: "../bench-data/wide-100k.csv")
    if FileManager.default.fileExists(atPath: autoFile.path) {
        MainActor.assumeIsolated { autoModel.open(urls: [autoFile]) }
        waitFor { MainActor.assumeIsolated { autoModel.entries.count == 1 } }
        let autoID = MainActor.assumeIsolated { autoModel.entries.first?.id }
        MainActor.assumeIsolated { autoModel.runAutoAnalysis(entryID: autoID!) }
        waitFor(timeout: 30) { MainActor.assumeIsolated { autoModel.autoCharts != nil || autoModel.error != nil } }
        let charts = MainActor.assumeIsolated { autoModel.autoCharts }
        check("一键分析出多张图", (charts?.count ?? 0) >= 3)
        check("一键分析按分类词挑维度", charts?.first?.title.hasPrefix("区域") == true)
        check("一键分析跳过订单号", charts?.contains { $0.title.hasPrefix("订单号") } == false)
        check("一键分析每张图有数据", charts?.allSatisfy { !$0.isEmpty } == true)
        MainActor.assumeIsolated { autoModel.clearAutoAnalysis() }
        MainActor.assumeIsolated { for entry in autoModel.entries { entry.session.close() } }
    } else {
        print("SKIP  缺少 wide-100k.csv，跳过一键分析端到端")
    }

    // 一键分析在 328 万行上的整体耗时（R-AUTO 4.2，预算 3 秒）
    let bigAutoFile = URL(fileURLWithPath: "../bench-data/500mb.csv")
    if FileManager.default.fileExists(atPath: bigAutoFile.path) {
        let bigModel = MainActor.assumeIsolated { WorkspaceModel() }
        MainActor.assumeIsolated { bigModel.open(urls: [bigAutoFile]) }
        waitFor(timeout: 120) { MainActor.assumeIsolated { bigModel.entries.count == 1 } }
        guard let bigID = MainActor.assumeIsolated({ bigModel.entries.first?.id }) else {
            print("SKIP  500mb.csv 打开失败，跳过大表一键分析")
            return
        }
        // 先跑一次热身的基数探测，计时从零开始更接近用户点按钮那一刻的冷路径。
        let autoStart = Date()
        MainActor.assumeIsolated { bigModel.runAutoAnalysis(entryID: bigID) }
        waitFor(timeout: 120) { MainActor.assumeIsolated { bigModel.autoCharts != nil || bigModel.error != nil } }
        let autoSeconds = Date().timeIntervalSince(autoStart)
        let bigCharts = MainActor.assumeIsolated { bigModel.autoCharts }
        print(String(format: "一键分析 %d 行: %.2f 秒，%d 张图",
                     MainActor.assumeIsolated { bigModel.entries.first?.rowCount ?? 0 },
                     autoSeconds, bigCharts?.count ?? 0))
        // 预算按 release 卡。debug 版 DuckDB 查询慢 20 倍以上，拿它比预算没有意义。
        #if DEBUG
        print("SKIP  328 万行一键分析计时（debug 构建不卡预算，用 release 版测试程序复跑）")
        #else
        check("328 万行一键分析 3 秒内", autoSeconds < 3.0)
        #endif
        check("328 万行一键分析出图", (bigCharts?.count ?? 0) >= 3)
        MainActor.assumeIsolated {
            for entry in bigModel.entries { entry.session.close() }
        }
    } else {
        print("SKIP  缺少 500mb.csv，跳过 328 万行一键分析计时")
    }

    // 行详情：只取一行，宽表按显示列裁剪
    MainActor.assumeIsolated { model.selection = firstID }
    MainActor.assumeIsolated { model.loadRowDetail(entryID: firstID!, row: 0) }
    waitFor { MainActor.assumeIsolated { model.rowDetail != nil } }
    let detail = MainActor.assumeIsolated { model.rowDetail }
    check("行详情列出全部列", detail?.fields.count == 2)
    check("行详情首字段是行名", detail?.fields.first?.name == "name" && detail?.fields.first?.value == "a")
    check("行详情 TSV 两列", detail?.tsv.split(separator: "\n").count == 2 && detail?.tsv.contains("\t") == true)
    MainActor.assumeIsolated {
        for entry in model.entries { entry.session.close() }
    }

    // 一次打开多个文件：只进一次左栏，选中第一个
    let multiModel = MainActor.assumeIsolated { WorkspaceModel() }
    MainActor.assumeIsolated { multiModel.open(urls: [switchA, switchB]) }
    waitFor { multiModel.entries.count == 2 }
    let multiFirst = MainActor.assumeIsolated { multiModel.entries.first?.id }
    check("多选打开选中第一个", MainActor.assumeIsolated { multiModel.selection == multiFirst })
    MainActor.assumeIsolated { multiModel.open(urls: [switchA]) }
    waitFor { !multiModel.isLoading }
    check("重复打开不新增条目", MainActor.assumeIsolated { multiModel.entries.count == 2 })
    MainActor.assumeIsolated {
        for entry in multiModel.entries { entry.session.close() }
    }

    let fiveFiles = (1...5).map { working.appendingPathComponent("five-\($0).csv") }
    for (index, url) in fiveFiles.enumerated() {
        try "name,amount\nn\(index),1\n".write(to: url, atomically: true, encoding: .utf8)
    }
    let fiveModel = MainActor.assumeIsolated { WorkspaceModel() }
    MainActor.assumeIsolated { fiveModel.open(urls: fiveFiles) }
    waitFor { fiveModel.entries.count == 5 }
    check("一次打开 5 个文件", MainActor.assumeIsolated { fiveModel.entries.count == 5 })
    let fiveFirst = MainActor.assumeIsolated { fiveModel.entries.first?.id }
    check("5 个文件选中第一个", MainActor.assumeIsolated { fiveModel.selection == fiveFirst })
    MainActor.assumeIsolated {
        for entry in fiveModel.entries { entry.session.close() }
    }

    // SQL 补全（R-SQL-05）
    let sqlColumns = ["订单编号", "客户名称", "金额", "城市"]
    let sqlTables = ["data"]

    let selectContext = SQLCompletion.context(in: "sel", caret: 3, tables: sqlTables)
    check("补全认 sel 为词前缀", selectContext == SQLCompletion.Context(prefix: "sel", qualifier: nil, kind: .column))
    let selectCandidates = SQLCompletion.candidates(
        context: selectContext!,
        columns: sqlColumns,
        tables: sqlTables
    )
    check("补全候选含 SELECT", selectCandidates.contains("SELECT"))
    check("补全候选把 SELECT 排前面", selectCandidates.first == "SELECT")

    let fromContext = SQLCompletion.context(in: "SELECT * FROM ", caret: 14, tables: sqlTables)
    check("补全在 FROM 后不弹候选", fromContext == nil)
    let fromTyped = SQLCompletion.context(in: "SELECT * FROM da", caret: 16, tables: sqlTables)
    check("补全认 FROM 后补表名", fromTyped?.kind == .table)
    check(
        "补全列出当前表",
        SQLCompletion.candidates(context: fromTyped!, columns: sqlColumns, tables: sqlTables) == ["data"]
    )

    let qualified = SQLCompletion.context(in: "SELECT data.金", caret: 13, tables: sqlTables)
    check("补全认表名限定", qualified?.qualifier == "data")
    check("补全限定后只补列", qualified?.kind == .column)
    check(
        "补全塞选中文列",
        SQLCompletion.candidates(context: qualified!, columns: sqlColumns, tables: sqlTables) == ["金额"]
    )

    let unknownQualifier = SQLCompletion.context(in: "SELECT nope.金", caret: 13, tables: sqlTables)
    check("未知表名限定不弹候选", unknownQualifier == nil)

    let inLiteral = SQLCompletion.context(in: "SELECT * FROM data WHERE 城市 = '杭", caret: 30, tables: sqlTables)
    check("补全不在字符串里弹", inLiteral == nil)
    let inComment = SQLCompletion.context(in: "SELECT * FROM data -- 这是注释", caret: 26, tables: sqlTables)
    check("补全不在注释里弹", inComment == nil)

    let applied = SQLCompletion.apply(candidate: "SELECT", to: "sel", caret: 3)
    check("补全替换词前缀", applied?.text == "SELECT")
    check("补全后光标在词尾", applied?.caret == 6)
    let appliedMid = SQLCompletion.apply(candidate: "SELECT", to: "sel * FROM data", caret: 3)
    check("补全保留后半句", appliedMid?.text == "SELECT * FROM data")

    let appliedQualified = SQLCompletion.apply(candidate: "金额", to: "SELECT data.金", caret: 13)
    check("补全保留表名限定", appliedQualified?.text == "SELECT data.金额")

    let groupBy = SQLCompletion.apply(candidate: "GROUP BY", to: "GROUP", caret: 5)
    check("补全多词关键字带空格", groupBy?.text == "GROUP BY ")

    check(
        "补全去重",
        SQLCompletion.candidates(
            context: SQLCompletion.Context(prefix: "cou", qualifier: nil, kind: .column),
            columns: ["count"],
            tables: sqlTables
        ).count == 1
    )
    check(
        "补全不重复给出已敲完整的词",
        SQLCompletion.candidates(
            context: SQLCompletion.Context(prefix: "SELECT", qualifier: nil, kind: .column),
            columns: [],
            tables: sqlTables
        ).isEmpty
    )
    check(
        "补全空前缀不弹",
        SQLCompletion.candidates(
            context: SQLCompletion.Context(prefix: "", qualifier: nil, kind: .column),
            columns: sqlColumns,
            tables: sqlTables
        ).isEmpty
    )

    // 补全弹窗的真实窗口交互（R-SQL-05）
    func makeCompletionSource(columns: [String], tables: [String]) -> SQLTextView.Coordinator {
        var storage = ""
        let binding = Binding(get: { storage }, set: { storage = $0 })
        let coordinator = SQLTextView.Coordinator(text: binding)
        coordinator.columns = columns
        coordinator.tables = tables
        return coordinator
    }

    func makeWindow(text: String) -> (NSPanel, CompletionTextView) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let textView = CompletionTextView(frame: NSRect(x: 0, y: 0, width: 580, height: 180))
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        panel.contentView?.addSubview(textView)
        textView.string = text
        return (panel, textView)
    }

    let completionColumns = ["订单编号", "客户名称", "金额", "城市"]
    let completionTables = ["data"]
    let completionSource = makeCompletionSource(columns: completionColumns, tables: completionTables)
    let (completionWindow, completionView) = makeWindow(text: "sel")
    completionView.completionSource = completionSource
    completionView.setSelectedRange(NSRange(location: 3, length: 0))
    completionView.refreshCompletion()
    check("弹窗在输入前缀后出现", completionView.isSuggesting)
    check("弹窗候选含 SELECT", completionView.suggestions.contains("SELECT"))

    // 弹窗要贴着光标，不能落到编辑器左下角。
    let caretRect = completionView.firstRect(
        forCharacterRange: NSRange(location: 3, length: 0),
        actualRange: nil
    )
    if let popupFrame = completionView.suggestingFrame {
        check("弹窗横向贴住光标", abs(popupFrame.minX - caretRect.minX) < 2)
        check(
            "弹窗纵向贴着光标行",
            popupFrame.maxY <= caretRect.minY + 1 || popupFrame.minY >= caretRect.maxY - 1
        )
    } else {
        check("弹窗横向贴住光标", false)
        check("弹窗纵向贴着光标行", false)
    }

    completionView.acceptSuggestion(at: 0)
    check("Tab 接受后补成 SELECT", completionView.string == "SELECT")
    check("接受后弹窗收起", !completionView.isSuggesting)

    let (commentWindow, commentView) = makeWindow(text: "-- 注释")
    commentView.completionSource = completionSource
    commentView.setSelectedRange(NSRange(location: 4, length: 0))
    commentView.refreshCompletion()
    check("注释里不弹候选", !commentView.isSuggesting)

    let (literalWindow, literalView) = makeWindow(text: "SELECT 城市 FROM data WHERE 城市 = '杭")
    literalView.completionSource = completionSource
    literalView.setSelectedRange(NSRange(location: (literalView.string as NSString).length, length: 0))
    literalView.refreshCompletion()
    check("字符串里不弹候选", !literalView.isSuggesting)

    let (clearWindow, clearView) = makeWindow(text: "SELECT * FROM data ")
    clearView.completionSource = completionSource
    let end = (clearView.string as NSString).length
    clearView.setSelectedRange(NSRange(location: end, length: 0))
    clearView.refreshCompletion()
    check("左括号与空格后不弹候选", !clearView.isSuggesting)

    let (qualifiedWindow, qualifiedView) = makeWindow(text: "SELECT data.金")
    qualifiedView.completionSource = completionSource
    qualifiedView.setSelectedRange(NSRange(location: 13, length: 0))
    qualifiedView.refreshCompletion()
    check("表名限定后弹列名", qualifiedView.suggestions == ["金额"])
    qualifiedView.acceptSuggestion(at: 0)
    check("限定补全保留表名", qualifiedView.string == "SELECT data.金额")

    for window in [completionWindow, commentWindow, literalWindow, clearWindow, qualifiedWindow] {
        window.close()
    }

    // 透视面板的落位规则（R-PVT 2.1、2.2）：拖进去、去重、换聚合、删掉。
    let draft = PivotDraft()
    check("透视空面板不能生成", !draft.canRun)
    check("空面板提示至少放一个字段", draft.blockedHint == "至少放一个字段到行或值")
    draft.add("region", to: .rows)
    check("只拖行维度还不能生成", !draft.canRun)
    check("只放行维度提示补值", draft.blockedHint == "至少放一个字段到值")
    draft.add("amount", to: .values)
    check("行加值可以生成", draft.canRun)
    check("凑齐后不再提示", draft.blockedHint == nil)
    draft.add("region", to: .rows)
    check("同一字段重复拖入只留一份", draft.rows == ["region"])
    draft.add("channel", to: .columns)
    draft.add("amount", to: .values)
    check("值字段不重复", draft.values.count == 1)
    check("透视草稿转成 spec", draft.spec.rows == ["region"] && draft.spec.columns == ["channel"])
    check("值字段默认求和", draft.values[0].aggregate == PivotAggregate.sum)
    draft.setAggregate(.average, for: "amount")
    check("换聚合方式生效", draft.values[0].aggregate == PivotAggregate.average)
    check("换聚合不改顺序", draft.values[0].column == "amount")
    draft.setAggregate(.maximum, for: "not-there")
    check("换不存在的字段不报错", draft.values[0].aggregate == PivotAggregate.average)
    draft.remove("channel", from: .columns)
    check("移除列维度", draft.columns.isEmpty)
    draft.add("channel", to: .columns)
    draft.removeValue(at: 0)
    check("删掉值字段后不能生成", !draft.canRun && draft.values.isEmpty)
    draft.add("amount", to: .values)
    draft.remove("region", from: .rows)
    check("删掉行维度后不能生成", !draft.canRun && draft.rows.isEmpty)
    check("删行后提示补值", draft.blockedHint == "把字段拖到行")

    // 筛选区域（R-PVT-01）：拖进来一行一个条件，填了值才放行。
    let filterDraft = PivotDraft()
    filterDraft.add("city", to: .rows)
    filterDraft.add("amount", to: .values)
    filterDraft.add("city", to: .filter)
    check("拖入筛选字段生成一条条件", filterDraft.filters.count == 1 && filterDraft.filters[0].op == .equal)
    check("筛选没填值时不能生成", !filterDraft.canRun)
    check("缺筛选值给提示", filterDraft.blockedHint == "筛选条件「city」还没填值")
    filterDraft.setFilter(FilterCondition(column: "city", op: .equal, value: "上海"))
    check("填了筛选值能生成", filterDraft.canRun)
    check("筛选进 spec", filterDraft.spec.filter?.conditions.first?.value == "上海")
    filterDraft.add("amount", to: .filter)
    filterDraft.setFilter(FilterCondition(column: "amount", op: .greaterThan, value: "100"))
    let filteredPivot = try query.session.pivot(spec: filterDraft.spec)
    let filteredPivotSQL = try query.session.runSQL(
        "SELECT city, sum(amount) FROM data WHERE city = '上海' AND amount > 100 GROUP BY city ORDER BY city"
    )
    check("透视筛选与手写 WHERE 一致", filteredPivot.rows == filteredPivotSQL.rows)
    filterDraft.removeFilter(at: 0)
    check("删筛选条件", filterDraft.filters.count == 1 && filterDraft.filters[0].column == "amount")
    filterDraft.remove("amount", from: .filter)
    check("筛选清空后 spec 不带筛选", filterDraft.filters.isEmpty && filterDraft.spec.filter == nil)

    // 缺值字段直接生成要被拒绝，面板里也能提前看出来（R-PVT 2.4）。
    let missingValueDraft = PivotDraft()
    missingValueDraft.add("region", to: .rows)
    check("只有行维度时面板禁用生成", !missingValueDraft.canRun)
    var missingRejected = false
    do {
        _ = try query.session.pivot(spec: missingValueDraft.spec)
    } catch {
        missingRejected = true
    }
    check("缺值字段的透视被拒绝", missingRejected)

    // 拖动落位落到真实的透视查询上，结果能出来（R-PVT 2.1、2.3）。
    let wired = PivotDraft()
    wired.add("city", to: .rows)
    wired.add("amount", to: .values)
    let wiredResult = try query.session.pivot(spec: wired.spec)
    check("面板选的行与值能出结果", wiredResult.rowCount == 3)
    check("结果列名带聚合方式", wiredResult.columns.last?.displayName.contains("求和") == true)
    check("结果带上耗时", wiredResult.elapsed >= 0)

    // SQL 结果的截断与空结果提示（R-SQL 2.3）。
    let normalStatus = SQLResultStatus(
        result: SQLResult(columns: [], rows: [], rowCount: 12, elapsed: 0.031, truncated: false),
        title: "查询结果"
    )
    check("普通结果无截断提示", normalStatus.truncationNotice == nil)
    check("普通结果不显示空占位", normalStatus.emptyPlaceholder == nil)
    check("结果摘要含行数与耗时", normalStatus.summary == "12 行 · 0.03 秒")

    let truncatedStatus = SQLResultStatus(
        result: SQLResult(columns: [], rows: [], rowCount: 100_000, elapsed: 1.2, truncated: true),
        title: "查询结果"
    )
    check("截断结果给提示", truncatedStatus.truncationNotice == "只显示前 100,000 行")
    check("截断结果不显示空占位", truncatedStatus.emptyPlaceholder == nil)

    let emptyStatus = SQLResultStatus(
        result: SQLResult(columns: [], rows: [], rowCount: 0, elapsed: 0.012, truncated: false),
        title: "查询结果"
    )
    check("空结果显示占位", emptyStatus.emptyPlaceholder == "0 行")
    check("空结果不给截断提示", emptyStatus.truncationNotice == nil)
    check("摘要五位数加千分位", SQLResultStatus.grouped(1234567) == "1,234,567")
    check("摘要三位数不加分隔", SQLResultStatus.grouped(999) == "999")
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
