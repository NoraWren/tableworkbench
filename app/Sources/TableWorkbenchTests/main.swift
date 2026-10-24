import Foundation
import AppKit
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

    var syntaxRejected = false
    do { _ = try query.session.runSQL("SELEC * FROM data") } catch { syntaxRejected = true }
    check("SQL 语法错误被拒绝", syntaxRejected)

    let emptySQL = try query.session.runSQL("SELECT * FROM data WHERE 1 = 0")
    check("SQL 空结果 0 行", emptySQL.rowCount == 0)

    let tempCreated = try query.session.runSQL("CREATE TEMP TABLE t AS SELECT 1 AS a")
    check("CREATE TEMP 成功", tempCreated.rowCount == 0)
    let tempRead = try query.session.runSQL("SELECT * FROM t")
    check("临时表可查询", tempRead.rows.first?.first == "1")

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

    // 列统计与导出
    let amountStats = try query.session.columnStats(column: "amount")
    check("金额统计总数 6", amountStats.totalRows == 6 && amountStats.nullCount == 0 && amountStats.distinctCount == 6)
    check("金额最小最大", amountStats.minValue == "30" && amountStats.maxValue == "400")
    check("金额均值 180", abs((amountStats.mean ?? 0) - 180) < 0.001)
    check("金额中位数 150", abs((amountStats.median ?? 0) - 150) < 0.001)
    check("直方图 20 桶且计数 6", amountStats.histogram.count == 20 && amountStats.histogram.reduce(0) { $0 + $1.count } == 6)

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
    let exported = try FileImporter.open(url: exportURL)
    check("CSV 导出行数 6", exported.session.rowCount == 6)

    let parquetURL = working.appendingPathComponent("export.parquet")
    _ = try query.session.export(to: parquetURL, format: .parquet)
    let exportedParquet = try DuckDBSession.openParquet(url: parquetURL)
    check("Parquet 导出行数 6", exportedParquet.rowCount == 6)

    let importedParquet = try FileImporter.open(url: parquetURL)
    check("Parquet 可再次打开", importedParquet.session.rowCount == 6)
    check("Parquet 编码标记", importedParquet.encoding == .parquet)
    check("Parquet 首行有值", try importedParquet.session.block(offset: 0, size: 1).rows.first?.first != nil)
    importedParquet.session.close()

    try query.session.apply(view: QueryView(filter: FilterGroup(join: .and, conditions: [
        FilterCondition(column: "city", op: .equal, value: "上海")
    ])))
    let filteredURL = working.appendingPathComponent("filtered.csv")
    _ = try query.session.export(to: filteredURL, format: .csv)
    let filteredExport = try FileImporter.open(url: filteredURL)
    check("筛选导出 4 行", filteredExport.session.rowCount == 4)
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
