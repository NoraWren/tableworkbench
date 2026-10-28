import DuckDB
import Foundation

/// 真实实现。连接以只读方式使用，任何写语句在进入引擎前被拦下。
public final class DuckDBSession: QuerySession, @unchecked Sendable {
    public let columns: [ColumnInfo]
    public let rowCount: Int
    public private(set) var resultCount: Int
    public private(set) var generation: Int = 0
    /// 行数 × 列数超过这个值就保留 Parquet 视图，否则物化。测试里会调小来覆盖视图分支。
    public static var parquetViewCellThreshold = 20_000_000

    /// 设 TW_LOG_BLOCK_SQL 后把每次取块用的 SQL 打到标准错误。
    /// R-GRID-02 的「首次显示只查一次块，SQL 里能看到 LIMIT 5000」靠它留证。
    static let logsBlockSQL = ProcessInfo.processInfo.environment["TW_LOG_BLOCK_SQL"] != nil
    /// 文本列类型冲突检查的抽样门槛，非空行超过它就只扫前这么多行。测试里会调小来覆盖抽样分支。
    public static var textProbeSampleThreshold = 200_000
    /// 平时的工作上限。导入期会临时抬高，物化完立刻收回这个值。
    public static let residentMemoryLimit = "1200MB"
    /// 导入期的工作上限。500 MB CSV 物化要 1.3 GB 出头的工作内存，卡在 1200MB 打开要 2.0 秒，
    /// 抬到 1.4 GB 是 1.5 秒；再往上没有额外收益，峰值反而继续涨。
    public static let importMemoryLimitBytes = 1_400_000_000
    /// 文件小于这个尺寸时，物化用不到导入上限，保持原样。
    public static let importMemoryLimitFileThreshold = 64 * 1024 * 1024
    /// 排序与筛选要把结果整表物化，这一段的工作集比导入期还大：1012 万行 × 20 列排序
    /// 用常驻的 1200MB 会一路落盘，实测 24.7 秒；给到 4 GB 之后 7 秒上下。
    /// 取物理内存的一半与 4 GB 的较小值，内存小的机器不至于被压到交换。
    public static var materializeMemoryLimit: String = {
        let halfOfRAM = ProcessInfo.processInfo.physicalMemory / 2
        let cap = min(halfOfRAM, 4 * 1024 * 1024 * 1024)
        return "\(max(1_200_000_000, cap))B"
    }()
    private var view: QueryView = .empty
    private var hasResultTable = false
    private var computedColumns: [(name: String, expression: String)] = []
    /// 按列缓存统计，配 generation 判断是否失效。
    private var statsCache: [String: (generation: Int, stats: ColumnStats)] = [:]
    /// 检查器累计发出的 SQL 条数，缓存命中不增加。测试用它确认切回已算过的列不再查库。
    public private(set) var statsQueryCount = 0
    private var distinctCache: [String: (generation: Int, count: Int)] = [:]
    private var database: Database?
    private var connection: Connection?
    /// 中断专用句柄。中断不能拿会话锁——正在跑的查询正握着它，拿了只会排在后面等它跑完。
    private let interruptHandle: Connection
    private let temporaryDirectory: URL
    private let lock = NSLock()
    private var closed = false
    /// 取块时用来定位行的列：CSV 物化表用 rowid，Parquet 视图用 __rid。
    private var orderColumn = "rowid"

    private init(
        database: Database,
        connection: Connection,
        temporaryDirectory: URL,
        columns: [ColumnInfo],
        rowCount: Int,
        orderColumn: String = "rowid"
    ) {
        self.database = database
        self.connection = connection
        self.interruptHandle = connection
        self.temporaryDirectory = temporaryDirectory
        self.columns = columns
        self.rowCount = rowCount
        self.resultCount = rowCount
        self.orderColumn = orderColumn
    }

    deinit {
        close()
    }

    public static func open(url: URL, format: CSVFormat) throws -> DuckDBSession {
        try open(source: .csv(url, format))
    }

    public static func openParquet(url: URL) throws -> DuckDBSession {
        try open(source: .parquet(url))
    }

    private enum Source {
        case csv(URL, CSVFormat)
        case parquet(URL)
    }

    /// 导入期的工作上限。只对 CSV 大文件放宽，Parquet 走视图、用不上。
    ///
    /// 500 MB CSV 物化 __base 要 1.3 GB 出头的工作内存。卡在 1200MB 时打开要 2.0 秒，
    /// 抬到 1.4 GB 是 1.5 秒；再往上（2 GB、4 GB）没有额外收益，峰值 RSS 却跟着涨。
    /// 中间那 0.4 秒具体花在哪还没验到底：duckdb_temporary_files() 全程 0 字节，
    /// 所以不是肉眼可见的落盘，更像是被上限压住时并行度起不来。见 R-DEC-15。
    private static func importMemoryLimit(for source: Source) -> String {
        guard case .csv(let url, _) = source else { return residentMemoryLimit }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size >= importMemoryLimitFileThreshold else { return residentMemoryLimit }
        return "\(importMemoryLimitBytes)B"
    }

    private static func open(source: Source) throws -> DuckDBSession {
        do {
            // 计时起点在 OpenTiming 里：拖放路径由松手那一刻算起，其他路径由进程启动算起。
            let mark = OpenTiming.mark
            let fileManager = FileManager.default
            let importLimit = importMemoryLimit(for: source)
            let temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent("tableworkbench-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            let database = try Database(store: .inMemory)
            let connection = try database.connect()
            // 导入期的工作上限比常驻上限高，见 importMemoryLimit 的注释。
            try connection.execute("SET memory_limit='\(importLimit)'")
            try connection.execute("SET temp_directory='\(temporaryDirectory.path.replacingOccurrences(of: "'", with: "''"))'")

            let createTable: String
            var useParquetView = false
            switch source {
            case .csv(let url, let format):
                let path = url.path.replacingOccurrences(of: "'", with: "''")
                let delimiter = format.delimiter == "\t" ? "\t" : String(format.delimiter)
                let delimiterLiteral = delimiter.replacingOccurrences(of: "'", with: "''")
                let header = format.hasHeader ? "true" : "false"
                createTable = """
                CREATE TABLE "__base" AS
                SELECT * FROM read_csv_auto('\(path)', delim='\(delimiterLiteral)', header=\(header), auto_detect=true)
                """
            case .parquet(let url):
                let path = url.path.replacingOccurrences(of: "'", with: "''")
                // 小表物化更划算（宽表按列投影走 Parquet 反而慢），大表留在视图里，打开不用拷贝。
                let probe = try connection.query("SELECT count(*) FROM read_parquet('\(path)')")
                let rows = Int(probe.column(at: 0).cast(to: Int64.self)[0] ?? 0)
                let described = try connection.query("DESCRIBE SELECT * FROM read_parquet('\(path)')")
                let columnCount = Int(described.rowCount)
                let materialize = rows * max(1, columnCount) <= DuckDBSession.parquetViewCellThreshold
                useParquetView = !materialize
                if materialize {
                    createTable = "CREATE TABLE \"__base\" AS SELECT * FROM read_parquet('\(path)')"
                } else {
                    createTable = """
                    CREATE VIEW "__base" AS
                    SELECT * EXCLUDE (file_row_number), file_row_number AS "__rid"
                    FROM read_parquet('\(path)', file_row_number=true)
                    """
                }
            }
            try connection.execute(createTable)
            mark("物化 __base")
            // 物化完成就把工作上限收回常驻值，导入期多要的内存随即还给分配器。
            try connection.execute("SET memory_limit='\(DuckDBSession.residentMemoryLimit)'")

            let described = try connection.query("DESCRIBE SELECT * FROM \"__base\"")
            mark("DESCRIBE")
            let nameColumn = described.column(at: 0).cast(to: String.self)
            let typeColumn = described.column(at: 1).cast(to: String.self)
            let describeCount = Int(described.rowCount)

            var rawNames: [String] = []
            var typeNames: [String] = []
            for index in 0..<describeCount {
                let raw = nameColumn[DBInt(index)] ?? "column_\(index + 1)"
                if raw == "__rid" { continue }
                rawNames.append(raw)
                typeNames.append(typeColumn[DBInt(index)] ?? "VARCHAR")
            }
            let displayNames = CSVSniffer.sanitizeColumnNames(rawNames)
            // data 视图只暴露真实列，__rid 仅内部取块用。
            let visibleColumns = rawNames.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ", ")
            try connection.execute("CREATE VIEW \"data\" AS SELECT \(visibleColumns) FROM \"__base\"")

            var columns: [ColumnInfo] = []
            columns.reserveCapacity(rawNames.count)
            for index in 0..<rawNames.count {
                columns.append(
                    ColumnInfo(
                        name: rawNames[index],
                        displayName: displayNames[index],
                        typeName: typeNames[index],
                        kind: ColumnKind.infer(fromTypeName: typeNames[index])
                    )
                )
            }

            let counted = try connection.query("SELECT count(*) FROM \"__base\"")
            let total = counted.column(at: 0).cast(to: Int64.self)[0] ?? 0
            mark("count(*)")

            let orderColumn = useParquetView ? "__rid" : "rowid"
            return DuckDBSession(
                database: database,
                connection: connection,
                temporaryDirectory: temporaryDirectory,
                columns: columns,
                rowCount: Int(total),
                orderColumn: orderColumn
            )
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError.wrap(error, step: "打开文件")
        }
    }

    public func apply(view: QueryView) throws {
        lock.lock()
        defer { lock.unlock() }

        guard !closed, let connection else {
            throw ImportError(userMessage: "数据源已关闭", technicalDetail: nil, recoverySuggestion: "重新打开文件。")
        }

        let known = Set(columns.map(\.name))
        for spec in view.sort where !known.contains(spec.column) {
            throw ImportError(userMessage: "排序列不存在", technicalDetail: spec.column, recoverySuggestion: "重新选择一个列。")
        }
        if let filter = view.filter {
            for condition in filter.conditions where !known.contains(condition.column) {
                throw ImportError(userMessage: "筛选列不存在", technicalDetail: condition.column, recoverySuggestion: "重新选择一个列。")
            }
        }

        let whereSQL = SQLBuilder.whereClause(view.filter)
        let orderSQL = SQLBuilder.orderBy(view.sort)

        do {
            try connection.execute("DROP TABLE IF EXISTS \"__result\"")
            hasResultTable = false

            if whereSQL.isEmpty && orderSQL.isEmpty {
                resultCount = rowCount
            } else {
                let columnsSQL = SQLBuilder.columnList(columns)
                let inner = [
                    "SELECT \(columnsSQL) FROM \"__base\"",
                    whereSQL,
                    orderSQL
                ].filter { !$0.isEmpty }.joined(separator: " ")
                let createResult = """
                CREATE TEMP TABLE "__result" AS
                SELECT \(columnsSQL) FROM (\(inner)) AS t
                """
                // 排序与筛选的结果集整表物化，工作集是这一路最贵的地方：临时借一个更高的
                // 内存上限，建完立刻收回常驻值，别让这笔开销跟着应用一直占着。
                try? connection.execute("SET memory_limit='\(DuckDBSession.materializeMemoryLimit)'")
                defer { try? connection.execute("SET memory_limit='\(DuckDBSession.residentMemoryLimit)'") }
                // 排序与筛选要把结果整表物化，这一段是千万行上最贵的操作，单独打点。
                OpenTiming.mark("物化 __result 开始")
                try connection.execute(createResult)
                OpenTiming.mark("物化 __result 完")
                hasResultTable = true
                let counted = try connection.query("SELECT count(*) FROM \"__result\"")
                resultCount = Int(counted.column(at: 0).cast(to: Int64.self)[0] ?? 0)
                OpenTiming.mark("__result 计数 完")
            }
            self.view = view
            generation += 1
        } catch {
            throw ImportError.wrap(error, step: "执行筛选")
        }
    }

    public var displayColumns: [ColumnInfo] {
        var result = columns
        for computed in computedColumns {
            result.append(ColumnInfo(
                name: computed.name,
                displayName: computed.name,
                typeName: "VARCHAR",
                kind: .text,
                isComputed: true
            ))
        }
        return result
    }

    public func addComputedColumn(name: String, expression: String) throws {
        lock.lock()
        defer { lock.unlock() }

        guard !closed, let connection else {
            throw ImportError(userMessage: "数据源已关闭", technicalDetail: nil, recoverySuggestion: "重新打开文件。")
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExpression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedExpression.isEmpty else {
            throw ImportError(userMessage: "列名和表达式都不能为空", technicalDetail: nil, recoverySuggestion: "填写后重试。")
        }
        guard !trimmedExpression.contains(";") else {
            throw ImportError(userMessage: "表达式里不能有分号", technicalDetail: nil, recoverySuggestion: "只写一段表达式。")
        }
        let existing = Set(columns.map(\.name) + computedColumns.map(\.name))
        guard !existing.contains(trimmedName) else {
            throw ImportError(userMessage: "列名已存在", technicalDetail: trimmedName, recoverySuggestion: "换一个列名。")
        }

        let probe = "SELECT (\(trimmedExpression)) AS v FROM \"__base\" LIMIT 1"
        try SQLGuard.validate(probe)
        do {
            _ = try connection.query(probe)
        } catch {
            throw ImportError(
                userMessage: "表达式无效",
                technicalDetail: String(describing: error),
                recoverySuggestion: "检查列名和运算符号。"
            )
        }
        computedColumns.append((trimmedName, trimmedExpression))
    }

    /// 去重计数，按列缓存；换筛选后 generation 变化会重新算。
    public func distinctCount(column: String) throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        guard !closed, let connection else {
            throw ImportError(userMessage: "数据源已关闭", technicalDetail: nil, recoverySuggestion: "重新打开文件。")
        }
        if let cached = distinctCache[column], cached.generation == generation {
            return cached.count
        }
        let table = hasResultTable ? "\"__result\"" : "\"__base\""
        do {
            let result = try connection.query(
                "SELECT count(DISTINCT \(SQLBuilder.quoteIdentifier(column))) FROM \(table)"
            )
            let count = Int(result.column(at: 0).cast(to: Int64.self)[0] ?? 0)
            distinctCache[column] = (generation, count)
            return count
        } catch {
            throw ImportError(userMessage: "统计失败", technicalDetail: String(describing: error), recoverySuggestion: "换一列再试。")
        }
    }

    public func columnStats(column: String) throws -> ColumnStats {
        lock.lock()
        defer { lock.unlock() }

        guard !closed, let connection else {
            throw ImportError(userMessage: "数据源已关闭", technicalDetail: nil, recoverySuggestion: "重新打开文件。")
        }
        guard let info = columns.first(where: { $0.name == column }) else {
            throw ImportError(userMessage: "列不存在", technicalDetail: column, recoverySuggestion: "重新选择一列。")
        }
        // 同一份数据、同一代查询里算过的列直接用缓存，切回来不再扫表。
        if let cached = statsCache[column], cached.generation == generation {
            return cached.stats
        }

        let table = hasResultTable ? "\"__result\"" : "\"__base\""
        let identifier = SQLBuilder.quoteIdentifier(column)
        let numeric = "TRY_CAST(\(identifier) AS DOUBLE)"
        let rowCountOrResult = hasResultTable ? resultCount : rowCount
        // 检查器发出的每条 SQL 都过这里，缓存命中时一条都不加，用来验证切列不重复查库。
        func statsQuery(_ sql: String) throws -> ResultSet {
            statsQueryCount += 1
            return try connection.query(sql)
        }
        // TW_STATS_TIMING 打开时把每段查询的耗时写到 stderr，bench 里用来定位瓶颈。
        let reportTiming = ProcessInfo.processInfo.environment["TW_STATS_TIMING"] != nil
        let totalStart = Foundation.Date()
        var phaseStart = totalStart
        func mark(_ label: String) {
            guard reportTiming else { return }
            let now = Foundation.Date()
            let line = String(format: "[stats] %@ %.3f 秒 (累计 %.3f)\n", label, now.timeIntervalSince(phaseStart), now.timeIntervalSince(totalStart))
            FileHandle.standardError.write(Data(line.utf8))
            phaseStart = now
        }

        do {
            // 数值聚合只给数值列拼：文本列上 median(TRY_CAST(x AS DOUBLE)) 会把整列
            // 转成 DOUBLE 再排序，1017 万行实测多花 0.4 秒，而文本列的均值中位数本来就该是空的。
            var aggregateTerms = [
                "count(*)",
                "count(\(identifier))",
                "count(DISTINCT \(identifier))",
                "CAST(min(\(identifier)) AS VARCHAR)",
                "CAST(max(\(identifier)) AS VARCHAR)"
            ]
            if info.kind.isNumeric {
                aggregateTerms += ["avg(\(numeric))", "median(\(numeric))", "stddev_pop(\(numeric))"]
            }
            if info.kind == .text {
                aggregateTerms += [
                    "min(length(\(identifier)))",
                    "max(length(\(identifier)))",
                    "count(*) FILTER (WHERE \(identifier) <> trim(\(identifier)))"
                ]
            }
            let aggregateSelect = "SELECT " + aggregateTerms.joined(separator: ", ") + " FROM \(table)"
            let aggregate = try statsQuery(aggregateSelect)
            mark("聚合")
            let total = Int(aggregate.column(at: 0).cast(to: Int64.self)[0] ?? 0)
            let nonNull = Int(aggregate.column(at: 1).cast(to: Int64.self)[0] ?? 0)
            let distinct = Int(aggregate.column(at: 2).cast(to: Int64.self)[0] ?? 0)
            let minValue = aggregate.column(at: 3).cast(to: String.self)[0]
            let maxValue = aggregate.column(at: 4).cast(to: String.self)[0]
            var nextColumn = 5
            var mean: Double?
            var median: Double?
            var deviation: Double?
            if info.kind.isNumeric {
                mean = aggregate.column(at: DBInt(nextColumn)).cast(to: Double.self)[0]
                median = aggregate.column(at: DBInt(nextColumn + 1)).cast(to: Double.self)[0]
                deviation = aggregate.column(at: DBInt(nextColumn + 2)).cast(to: Double.self)[0]
                nextColumn += 3
            }
            var minLength: Int?
            var maxLength: Int?
            var whitespaceCount: Int?
            if info.kind == .text {
                minLength = Int(aggregate.column(at: DBInt(nextColumn)).cast(to: Int64.self)[0] ?? 0)
                maxLength = Int(aggregate.column(at: DBInt(nextColumn + 1)).cast(to: Int64.self)[0] ?? 0)
                whitespaceCount = Int(aggregate.column(at: DBInt(nextColumn + 2)).cast(to: Int64.self)[0] ?? 0)
            }

            var topValues: [TopValue] = []
            // 按原列分组、只在输出时转字符串：GROUP BY CAST(x AS VARCHAR) 要把 1000 万行
            // 全部转成字符串再做哈希分组，金额列实测 0.41 秒，按原列分组只要 0.28 秒。
            let top = try statsQuery("""
            SELECT CAST(\(identifier) AS VARCHAR) AS v, count(*) AS c
            FROM \(table) WHERE \(identifier) IS NOT NULL
            GROUP BY \(identifier) ORDER BY 2 DESC, 1 ASC LIMIT 10
            """)
            mark("top-values")
            let topValueColumn = top.column(at: 0).cast(to: String.self)
            let topCountColumn = top.column(at: 1).cast(to: Int64.self)
            for index in 0..<Int(top.rowCount) {
                topValues.append(TopValue(
                    value: topValueColumn[DBInt(index)] ?? "",
                    count: Int(topCountColumn[DBInt(index)] ?? 0)
                ))
            }

            var histogram: [HistogramBucket] = []
            if info.kind.isNumeric, let minValue, let maxValue,
               let lower = Double(minValue), let upper = Double(maxValue), upper > lower {
                let step = (upper - lower) / 20
                // 桶号必须返回 BIGINT：duckdb-swift 用 cast(to: Int64.self) 读 INTEGER 会全读成 nil，
                // 那些行会被当成第 0 桶，整列数据挤在一根柱子上。
                let bucketQuery = try statsQuery("""
                SELECT CAST(least(19, greatest(0, CAST(floor((\(numeric) - \(lower)) / \(step)) AS INTEGER))) AS BIGINT) AS b, count(*)
                FROM \(table) WHERE \(identifier) IS NOT NULL AND \(numeric) IS NOT NULL
                GROUP BY b ORDER BY b
                """)
                mark("直方图")
                var counts = Array(repeating: 0, count: 20)
                let bucketColumn = bucketQuery.column(at: 0).cast(to: Int64.self)
                let countColumn = bucketQuery.column(at: 1).cast(to: Int64.self)
                for index in 0..<Int(bucketQuery.rowCount) {
                    let bucket = Int(bucketColumn[DBInt(index)] ?? 0)
                    let count = Int(countColumn[DBInt(index)] ?? 0)
                    // SQL 已经用 least/greatest 把桶号夹到 0..19，这里只再兜一次底。
                    let clamped = min(19, max(0, bucket))
                    counts[clamped] += count
                }
                for index in 0..<20 {
                    histogram.append(HistogramBucket(
                        lower: lower + step * Double(index),
                        upper: lower + step * Double(index + 1),
                        count: counts[index]
                    ))
                }
            }

            var numericCount = nonNull
            var nonNumericExamples: [String] = []
            var numericSampleRows: Int?
            if info.kind == .text, nonNull > 0 {
                // 大表上 TRY_CAST 全表扫一遍要 0.3-0.4 秒，而类型冲突只是提示，
                // 换成前 20 万行抽样（0.04 秒），命中时按样本比例推算行数并在界面标“抽样”。
                let sampleLimit = DuckDBSession.textProbeSampleThreshold
                let sampling = nonNull > sampleLimit
                let source = sampling ? "(SELECT \(identifier) FROM \(table) WHERE \(identifier) IS NOT NULL LIMIT \(sampleLimit))" : table
                let numericQuery = try statsQuery("""
                SELECT count(*), count(*) FILTER (WHERE TRY_CAST(\(identifier) AS DOUBLE) IS NOT NULL)
                FROM \(source)
                """)
                mark("数值探针")
                let sampleNonNull = Int(numericQuery.column(at: 0).cast(to: Int64.self)[0] ?? 0)
                let sampleNumeric = Int(numericQuery.column(at: 1).cast(to: Int64.self)[0] ?? 0)
                if sampling {
                    numericSampleRows = sampleNonNull
                    numericCount = min(nonNull, Int((Double(sampleNumeric) / Double(max(1, sampleNonNull)) * Double(nonNull)).rounded()))
                } else {
                    numericCount = sampleNumeric
                }
                if numericCount > 0 && numericCount < nonNull {
                    // 同一列里反例经常重复（比如几千行都是“—”、几十万行都是 abc），
                    // 取两条一样的没有意义，先去重再取两个不同的值。
                    let examples = try statsQuery("""
                    SELECT DISTINCT CAST(\(identifier) AS VARCHAR) AS v FROM \(table)
                    WHERE \(identifier) IS NOT NULL AND TRY_CAST(\(identifier) AS DOUBLE) IS NULL
                    ORDER BY 1 LIMIT 2
                    """)
                    let exampleColumn = examples.column(at: 0).cast(to: String.self)
                    for index in 0..<Int(examples.rowCount) {
                        if let value = exampleColumn[DBInt(index)] {
                            nonNumericExamples.append(value)
                        }
                    }
                }
            }

            var timeBuckets: [TimeBucket] = []
            if info.kind == .date || info.kind == .timestamp {
                let timeQuery = try statsQuery("""
                SELECT CAST(date_trunc('day', CAST(\(identifier) AS TIMESTAMP)) AS VARCHAR) AS d, CAST(count(*) AS BIGINT) AS c
                FROM \(table) WHERE \(identifier) IS NOT NULL
                GROUP BY 1 ORDER BY 1 LIMIT 62
                """)
                let labelColumn = timeQuery.column(at: 0).cast(to: String.self)
                let countColumn = timeQuery.column(at: 1).cast(to: Int64.self)
                for index in 0..<Int(timeQuery.rowCount) {
                    timeBuckets.append(TimeBucket(
                        label: labelColumn[DBInt(index)] ?? "",
                        count: Int(countColumn[DBInt(index)] ?? 0)
                    ))
                }
            }

            let stats = ColumnStats(
                column: column,
                typeName: info.typeName,
                kind: info.kind,
                totalRows: total,
                nullCount: total - nonNull,
                distinctCount: distinct,
                minValue: minValue,
                maxValue: maxValue,
                mean: mean,
                median: median,
                standardDeviation: deviation,
                topValues: topValues,
                histogram: histogram,
                timeBuckets: timeBuckets,
                numericCount: numericCount,
                nonNumericExamples: nonNumericExamples,
                numericSampleRows: numericSampleRows,
                minLength: minLength,
                maxLength: maxLength,
                whitespaceCount: whitespaceCount
            )
            statsCache[column] = (generation, stats)
            return stats
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError(userMessage: "统计失败", technicalDetail: String(describing: error), recoverySuggestion: "换一列再试。")
        }
    }

    public func export(to url: URL, format: ExportFormat) throws -> Int {
        try export(to: url, format: format, scope: .view)
    }

    public func export(to url: URL, format: ExportFormat, scope: ExportScope) throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        guard !closed, let connection else {
            throw ImportError(userMessage: "数据源已关闭", technicalDetail: nil, recoverySuggestion: "重新打开文件。")
        }

        let columnsSQL = SQLBuilder.columnList(columns)
        let source: String
        let expectedRows: Int
        var snapshotCreated = false

        switch scope {
        case .view:
            source = "SELECT \(columnsSQL) FROM \(hasResultTable ? "\"__result\"" : "\"__base\"")"
            expectedRows = resultCount
        case .all:
            source = "SELECT \(columnsSQL) FROM \"__base\""
            expectedRows = rowCount
        case .rows(let selected):
            let valid = selected.filter { $0 >= 0 && $0 < resultCount }
            guard !valid.isEmpty else {
                throw ImportError(
                    userMessage: "没有选中行",
                    technicalDetail: nil,
                    recoverySuggestion: "先在表格里选中要导出的行，或者改选当前视图。"
                )
            }
            let viewQuery = currentViewSelect(columnsSQL: columnsSQL)
            let indices = valid.map(String.init).joined(separator: ",")
            do {
                try connection.execute("DROP TABLE IF EXISTS \"__export_rows\"")
                try connection.execute("""
                CREATE TEMP TABLE "__export_rows" AS
                SELECT *, row_number() OVER () - 1 AS "__row" FROM (\(viewQuery)) AS t
                """)
                snapshotCreated = true
            } catch {
                throw ImportError(
                    userMessage: "导出失败",
                    technicalDetail: String(describing: error),
                    recoverySuggestion: "换一个位置再试。"
                )
            }
            source = "SELECT \(columnsSQL) FROM \"__export_rows\" WHERE \"__row\" IN (\(indices)) ORDER BY \"__row\""
            expectedRows = valid.count
        }

        defer {
            if snapshotCreated {
                try? connection.execute("DROP TABLE IF EXISTS \"__export_rows\"")
            }
        }

        let temporary = url.appendingPathExtension("tmp-\(UUID().uuidString)")
        try? FileManager.default.removeItem(at: temporary)

        let destination = temporary.path.replacingOccurrences(of: "'", with: "''")
        let options: String
        switch format {
        case .csv:
            options = "FORMAT CSV, HEADER, DELIMITER ','"
        case .parquet:
            options = "FORMAT PARQUET, COMPRESSION SNAPPY"
        }
        let sql = "COPY (\(source)) TO '\(destination)' (\(options))"

        do {
            try connection.execute(sql)
            switch format {
            case .csv:
                try moveWithBOM(from: temporary, to: url)
            case .parquet:
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                try FileManager.default.moveItem(at: temporary, to: url)
            }
            return expectedRows
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw ImportError(
                userMessage: "导出失败",
                technicalDetail: String(describing: error),
                recoverySuggestion: "确认目标目录有写权限，换一个位置再试。"
            )
        }
    }

    /// 当前视图（筛选 + 排序）的完整查询，选中行导出与网格取块用的是同一套条件。
    private func currentViewSelect(columnsSQL: String) -> String {
        let table = hasResultTable ? "\"__result\"" : "\"__base\""
        if hasResultTable {
            return "SELECT \(columnsSQL) FROM \(table)"
        }
        let whereSQL = SQLBuilder.whereClause(view.filter)
        let orderSQL = SQLBuilder.orderBy(view.sort)
        let parts = ["SELECT \(columnsSQL) FROM \(table)", whereSQL, orderSQL].filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    /// Excel 只有看到 BOM 才按 UTF-8 打开 CSV，这里在文件头补上，正文按 1MB 流式拷贝。
    private func moveWithBOM(from temporary: URL, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        FileManager.default.createFile(atPath: url.path, contents: Data([0xEF, 0xBB, 0xBF]))
        let output = try FileHandle(forWritingTo: url)
        let input = try FileHandle(forReadingFrom: temporary)
        defer {
            try? input.close()
            try? output.close()
            try? FileManager.default.removeItem(at: temporary)
        }
        try output.seekToEnd()
        while true {
            let chunk = try input.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            try output.write(contentsOf: chunk)
        }
    }

    /// 透视结果只要数据，图表和大部分调用方走这条。表头层级走 `pivotWithHeader`。
    public func pivot(spec: PivotSpec) throws -> SQLResult {
        try pivotWithHeader(spec: spec).result
    }

    /// 透视结果带表头层级，给结果网格渲染多层表头用。
    public func pivotWithHeader(spec: PivotSpec) throws -> PivotResult {
        lock.lock()
        defer { lock.unlock() }

        guard !closed, let connection else {
            throw ImportError(userMessage: "数据源已关闭", technicalDetail: nil, recoverySuggestion: "重新打开文件。")
        }
        let table = try validatePivot(spec)
        let started = Foundation.Date()

        do {
            let plan = try pivotPlan(spec: spec, connection: connection, table: table)
            let result = try executeSelect(plan.sql, connection: connection, started: started)
            guard result.rowCount <= 5000 else {
                throw ImportError(
                    userMessage: "行维度太多了",
                    technicalDetail: "去重后超过 5000 行",
                    recoverySuggestion: "换一个基数更低的字段，或先加筛选。"
                )
            }
            // 表头层级由配置和列组合推出来，不占查询时间，随结果一起回到主线程。
            return PivotResult(result: result, header: PivotHeader.build(spec: spec, combos: plan.combos))
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError(
                userMessage: "透视执行失败",
                technicalDetail: String(describing: error),
                recoverySuggestion: "减少维度后重试。"
            )
        }
    }

    /// 只把透视配置翻译成 SQL，不执行。给界面上的“在 SQL 抽屉复现”用，
    /// 和执行走同一份拼装逻辑，所以两者结果必然一致。
    public func pivotSQL(spec: PivotSpec) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        guard !closed, let connection else {
            throw ImportError(userMessage: "数据源已关闭", technicalDetail: nil, recoverySuggestion: "重新打开文件。")
        }
        _ = try validatePivot(spec)
        // 给用户看的 SQL 用 data 视图。同样的行、同样的列，比内部表名好读。
        let table = hasResultTable ? "\"__result\"" : "\"data\""
        do {
            return try pivotStatement(spec: spec, connection: connection, table: table)
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError(
                userMessage: "透视 SQL 生成失败",
                technicalDetail: String(describing: error),
                recoverySuggestion: "检查字段后重试。"
            )
        }
    }

    /// 校验字段并返回要查的表。表格上有筛选时查物化出来的 __result，否则查 __base。
    private func validatePivot(_ spec: PivotSpec) throws -> String {
        guard spec.isValid else {
            throw ImportError(
                userMessage: "透视配置不完整",
                technicalDetail: "至少需要一个行字段和一个值字段",
                recoverySuggestion: "把字段拖到行和值区域。"
            )
        }

        let known = Set(columns.map(\.name))
        let filterFields = (spec.filter?.conditions ?? []).map(\.column)
        let allFields = spec.rows + spec.columns + spec.values.map(\.column) + filterFields
        for field in allFields where !known.contains(field) {
            throw ImportError(userMessage: "字段不存在", technicalDetail: field, recoverySuggestion: "重新选择字段。")
        }
        return hasResultTable ? "\"__result\"" : "\"__base\""
    }

    /// 拼 SQL 的同时把列组合带出来。表头层级要靠这份组合算，两次查库没必要。
    private struct PivotPlan {
        let sql: String
        let combos: [[String]]
    }

    private func pivotStatement(spec: PivotSpec, connection: Connection, table: String) throws -> String {
        try pivotPlan(spec: spec, connection: connection, table: table).sql
    }

    private func pivotPlan(spec: PivotSpec, connection: Connection, table: String) throws -> PivotPlan {
        // 面板里的筛选和表格上的筛选叠加，两个都生效。
        let whereSQL = SQLBuilder.whereClause(spec.filter)
        let fromSQL = whereSQL.isEmpty ? table : "\(table) \(whereSQL)"
        let rowSQL = spec.rows.map(pivotLabel).joined(separator: ", ")
        let rowAliases = spec.rows.map(SQLBuilder.quoteIdentifier).joined(separator: ", ")
        let rowSelect = spec.rows
            .map { "\(pivotLabel($0)) AS \(SQLBuilder.quoteIdentifier($0))" }
            .joined(separator: ", ")

        var selectParts = [rowSelect]
        var combos: [[String]] = []
        if spec.columns.isEmpty {
            for value in spec.values {
                selectParts.append("\(aggregateSQL(value, condition: nil)) AS \(SQLBuilder.quoteIdentifier(value.title))")
            }
        } else {
            let columnSQL = spec.columns.map { "\(pivotLabel($0)) AS \(SQLBuilder.quoteIdentifier($0))" }
                .joined(separator: ", ")
            // 表头按前缀合并，组合必须按维度顺序排。DuckDB 不保证 DISTINCT 的顺序，这里显式排。
            let orderSQL = spec.columns.map { pivotLabel($0) }.joined(separator: ", ")
            let combosResult = try connection.query(
                "SELECT DISTINCT \(columnSQL) FROM \(fromSQL) ORDER BY \(orderSQL) LIMIT 201"
            )
            let comboCount = Int(combosResult.rowCount)
            guard comboCount <= 200 else {
                throw ImportError(
                    userMessage: "列维度太多了",
                    technicalDetail: "去重后超过 200 个组合",
                    recoverySuggestion: "换一个基数更低的列，或改用行维度。"
                )
            }
            guard comboCount > 0 else {
                throw ImportError(userMessage: "列维度没有可用值", technicalDetail: nil, recoverySuggestion: "换一个字段。")
            }

            var typed: [Column<String>] = []
            for index in 0..<Int(combosResult.columnCount) {
                typed.append(combosResult.column(at: DBInt(index)).cast(to: String.self))
            }
            combos.reserveCapacity(comboCount)
            for rowIndex in 0..<comboCount {
                var combo: [String] = []
                for column in typed {
                    combo.append(column[DBInt(rowIndex)] ?? "")
                }
                combos.append(combo)
            }

            for value in spec.values {
                for combo in combos {
                    let condition = zip(spec.columns, combo)
                        .map { "\(pivotLabel($0.0)) = \(SQLBuilder.literal($0.1))" }
                        .joined(separator: " AND ")
                    let name = "\(value.title) / \(combo.joined(separator: " / "))"
                    selectParts.append("\(aggregateSQL(value, condition: condition)) AS \(SQLBuilder.quoteIdentifier(name))")
                }
            }
        }

        // 多取一行用来判断基数：超过上限就报错，不再单独跑一遍 DISTINCT 计数。
        let rowLimit = 5001
        let sql = "SELECT \(selectParts.joined(separator: ", ")) FROM \(fromSQL) GROUP BY \(rowSQL) ORDER BY \(rowAliases) LIMIT \(rowLimit)"
        return PivotPlan(sql: sql, combos: combos)
    }

    private func aggregateSQL(_ value: PivotValue, condition: String?) -> String {
        let column = SQLBuilder.quoteIdentifier(value.column)
        let inner = condition.map { "CASE WHEN \($0) THEN \(column) END" } ?? column
        switch value.aggregate {
        case .sum: return "SUM(\(inner))"
        case .count: return "COUNT(\(inner))"
        case .countDistinct: return "COUNT(DISTINCT \(inner))"
        case .average: return "AVG(\(inner))"
        case .minimum: return "MIN(\(inner))"
        case .maximum: return "MAX(\(inner))"
        }
    }

    /// 透视表里 NULL 显示为 (空)，空字符串显示为 (空白)，两者不合并。
    private func pivotLabel(_ column: String) -> String {
        let identifier = SQLBuilder.quoteIdentifier(column)
        return "CASE WHEN \(identifier) IS NULL THEN '(空)' WHEN CAST(\(identifier) AS VARCHAR) = '' THEN '(空白)' ELSE CAST(\(identifier) AS VARCHAR) END"
    }

    public func runSQL(_ sql: String) throws -> SQLResult {
        lock.lock()
        defer { lock.unlock() }

        guard !closed, let connection else {
            throw ImportError(userMessage: "数据源已关闭", technicalDetail: nil, recoverySuggestion: "重新打开文件。")
        }

        var statement = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        while statement.hasSuffix(";") {
            statement.removeLast()
            statement = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !statement.isEmpty else {
            throw ImportError(userMessage: "SQL 是空的", technicalDetail: nil, recoverySuggestion: "写一条 SELECT 再运行。")
        }

        try SQLGuard.validate(statement)

        let keyword = statement
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map { String($0).uppercased() } ?? ""

        let started = Foundation.Date()
        do {
            switch keyword {
            case "SELECT", "WITH":
                return try executeSelect(statement, connection: connection, started: started)
            case "DESCRIBE", "SUMMARIZE":
                return try executeSelect(statement, connection: connection, started: started, applyLimit: false)
            case "CREATE":
                guard statement.uppercased().hasPrefix("CREATE TEMP") else {
                    throw ImportError(
                        userMessage: "只允许创建临时表或临时视图",
                        technicalDetail: "CREATE 语句必须以 CREATE TEMP 开头",
                        recoverySuggestion: "改用 CREATE TEMP TABLE。"
                    )
                }
                try connection.execute(statement)
                return SQLResult(columns: [], rows: [], rowCount: 0, elapsed: Foundation.Date().timeIntervalSince(started), truncated: false)
            default:
                throw ImportError(
                    userMessage: "只支持查询语句",
                    technicalDetail: "语句以 \(keyword) 开头",
                    recoverySuggestion: "用 SELECT、WITH、DESCRIBE 或 SUMMARIZE。"
                )
            }
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError(
                userMessage: "SQL 执行失败",
                technicalDetail: String(describing: error),
                recoverySuggestion: "检查语法和列名后重试。"
            )
        }
    }

    private func executeSelect(
        _ statement: String,
        connection: Connection,
        started: Foundation.Date,
        applyLimit: Bool = true
    ) throws -> SQLResult {
        let maxRows = 100_000
        var columnNames: [String] = []
        var columnTypes: [String] = []
        if applyLimit {
            let described = try connection.query("DESCRIBE \(statement)")
            let nameColumn = described.column(at: 0).cast(to: String.self)
            let typeColumn = described.column(at: 1).cast(to: String.self)
            for index in 0..<Int(described.rowCount) {
                columnNames.append(nameColumn[DBInt(index)] ?? "column_\(index + 1)")
                columnTypes.append(typeColumn[DBInt(index)] ?? "VARCHAR")
            }
        }

        let projection = columnNames.isEmpty
            ? "*"
            : columnNames.map {
                "CAST(\(SQLBuilder.quoteIdentifier($0)) AS VARCHAR) AS \(SQLBuilder.quoteIdentifier($0))"
            }.joined(separator: ", ")
        let query = applyLimit
            ? "SELECT \(projection) FROM (\(statement)) AS __sql LIMIT \(maxRows + 1)"
            : statement
        let result = try connection.query(query)

        let columnCount = Int(result.columnCount)
        var columns: [ColumnInfo] = []
        columns.reserveCapacity(columnCount)
        for index in 0..<columnCount {
            let name = result.columnName(at: DBInt(index))
            // 取数时统一转成 VARCHAR，但类型要按 DESCRIBE 的原文留着：
            // 界面靠它决定右对齐、要不要收掉双精度的尾巴，索引到类型就全退化成文本了。
            let typeName = index < columnTypes.count ? columnTypes[index] : "VARCHAR"
            columns.append(ColumnInfo(
                name: name,
                displayName: name,
                typeName: typeName,
                kind: ColumnKind.infer(fromTypeName: typeName)
            ))
        }

        let total = Int(result.rowCount)
        let keep = min(total, maxRows)
        var typed: [Column<String>] = []
        typed.reserveCapacity(columnCount)
        for index in 0..<columnCount {
            typed.append(result.column(at: DBInt(index)).cast(to: String.self))
        }

        var rows: [[String?]] = []
        rows.reserveCapacity(keep)
        for rowIndex in 0..<keep {
            var row: [String?] = []
            row.reserveCapacity(columnCount)
            for column in typed {
                row.append(column[DBInt(rowIndex)])
            }
            rows.append(row)
        }

        return SQLResult(
            columns: columns,
            rows: rows,
            rowCount: keep,
            elapsed: Foundation.Date().timeIntervalSince(started),
            truncated: total > maxRows
        )
    }

    public func block(offset: Int, size: Int) throws -> TableBlock {
        try block(offset: offset, size: size, columns: displayColumns)
    }

    public func block(offset: Int, size: Int, columns requested: [ColumnInfo]) throws -> TableBlock {
        lock.lock()
        defer { lock.unlock() }

        guard !closed, let connection else {
            throw ImportError(
                userMessage: "数据源已关闭",
                technicalDetail: nil,
                recoverySuggestion: "重新打开文件。"
            )
        }

        let safeOffset = max(0, offset)
        let safeSize = max(0, size)
        if resultCount == 0 || safeOffset >= resultCount {
            return TableBlock(offset: safeOffset, rows: [])
        }
        guard let selectList = selectListSQL(for: requested) else {
            return TableBlock(offset: safeOffset, rows: [])
        }
        let table = hasResultTable ? "\"__result\"" : "\"__base\""
        let upperBound = safeOffset + safeSize
        // __result 是物化表，用 rowid；只有直接查 Parquet 视图时才用 __rid。
        let order = hasResultTable ? "rowid" : orderColumn
        let sql: String
        if order == "rowid" {
            // 物化表按插入序返回（DuckDB 默认 preserve_insertion_order），浅层取块用
            // LIMIT/OFFSET 能直接停在所需行，不必像虚拟 rowid 那样为了过滤把整表扫一遍。
            sql = "SELECT \(selectList) FROM \(table) LIMIT \(safeSize) OFFSET \(safeOffset)"
        } else {
            sql = "SELECT \(selectList) FROM \(table) WHERE \(order) >= \(safeOffset) AND \(order) < \(upperBound) ORDER BY \(order)"
        }
        if DuckDBSession.logsBlockSQL {
            OpenTiming.append("[block] \(sql)\n")
        }

        do {
            let result = try connection.query(sql)
            return tableBlock(from: result, offset: safeOffset)
        } catch {
            throw ImportError.wrap(error, step: "读取数据")
        }
    }

    /// 只取排序与筛选后的前若干行，给「大表先出首屏」用。
    /// DuckDB 对 ORDER BY + LIMIT 走堆式 top-N，不用把整表排完：千万行取 5000 行实测 0.61 秒，
    /// 而整表物化要 5–8 秒。不带排序和筛选时没有预览的意义，返回 nil 让调用方走原路径。
    public func previewBlock(view: QueryView, columns requested: [ColumnInfo], limit: Int) throws -> TableBlock? {
        lock.lock()
        defer { lock.unlock() }

        guard !closed, let connection else { return nil }
        let whereSQL = SQLBuilder.whereClause(view.filter)
        let orderSQL = SQLBuilder.orderBy(view.sort)
        guard !whereSQL.isEmpty || !orderSQL.isEmpty else { return nil }
        guard let selectList = selectListSQL(for: requested) else { return nil }

        let inner = [
            "SELECT \(selectList) FROM \"__base\"",
            whereSQL,
            orderSQL
        ].filter { !$0.isEmpty }.joined(separator: " ")
        let sql = "SELECT * FROM (\(inner)) AS t LIMIT \(max(0, limit))"
        if DuckDBSession.logsBlockSQL {
            OpenTiming.append("[preview] \(sql)\n")
        }
        do {
            let result = try connection.query(sql)
            return tableBlock(from: result, offset: 0)
        } catch {
            throw ImportError.wrap(error, step: "预览排序结果")
        }
    }

    /// 一组列翻译成 SELECT 列表。计算列走表达式，普通列按名字投影。
    private func selectListSQL(for requested: [ColumnInfo]) -> String? {
        var parts: [String] = []
        parts.reserveCapacity(requested.count)
        for info in requested {
            if info.isComputed {
                if let computed = computedColumns.first(where: { $0.name == info.name }) {
                    parts.append("CAST((\(computed.expression)) AS VARCHAR) AS \(SQLBuilder.quoteIdentifier(computed.name))")
                }
            } else {
                parts.append(SQLBuilder.selectList([info]))
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// 结果集转成表格块，取块与首屏预览共用。
    private func tableBlock(from result: ResultSet, offset: Int) -> TableBlock {
        let resultRows = Int(result.rowCount)
        var typed: [Column<String>] = []
        typed.reserveCapacity(Int(result.columnCount))
        for index in 0..<Int(result.columnCount) {
            typed.append(result.column(at: DBInt(index)).cast(to: String.self))
        }

        var rows: [[String?]] = []
        rows.reserveCapacity(resultRows)
        for rowIndex in 0..<resultRows {
            var row: [String?] = []
            row.reserveCapacity(typed.count)
            for column in typed {
                row.append(column[DBInt(rowIndex)])
            }
            rows.append(row)
        }
        return TableBlock(offset: offset, rows: rows)
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        connection = nil
        database = nil
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    /// 打断正在这条连接上跑的查询。可从任意线程调用，不需要会话锁。
    /// 被打断的查询会以错误返回，调用方自己决定怎么呈现。
    public func interrupt() {
        interruptHandle.interrupt()
    }

    private static func quoteIdentifier(_ name: String) -> String {
        "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// 只读校验。所有外部输入的 SQL 先过这一层。
public enum SQLGuard {
    private static let forbidden = [
        "DROP", "DELETE", "INSERT", "UPDATE", "ALTER", "ATTACH", "DETACH",
        "INSTALL", "LOAD", "PRAGMA", "EXPORT", "COPY", "SET", "TRUNCATE"
    ]

    public static func validate(_ sql: String) throws {
        let upper = stripLiterals(sql).uppercased()
        for keyword in forbidden {
            if containsKeyword(upper, keyword) {
                throw ImportError(
                    userMessage: "分析模式只允许只读查询",
                    technicalDetail: "语句包含被禁止的关键字：\(keyword)",
                    recoverySuggestion: "去掉写操作后重试；需要临时表时使用 CREATE TEMP TABLE。"
                )
            }
        }
    }

    /// 去掉单引号和双引号里的内容，避免把普通字符串当成关键字。
    private static func stripLiterals(_ sql: String) -> String {
        var result = ""
        var inSingle = false
        var inDouble = false
        for character in sql {
            if character == "'" && !inDouble {
                inSingle.toggle()
                result.append(" ")
                continue
            }
            if character == "\"" && !inSingle {
                inDouble.toggle()
                result.append(" ")
                continue
            }
            result.append(inSingle || inDouble ? " " : character)
        }
        return result
    }

    private static func containsKeyword(_ sql: String, _ keyword: String) -> Bool {
        var searchStart = sql.startIndex
        while let range = sql.range(of: keyword, range: searchStart..<sql.endIndex) {
            let before = range.lowerBound == sql.startIndex ? " " : String(sql[sql.index(before: range.lowerBound)])
            let after = range.upperBound == sql.endIndex ? " " : String(sql[range.upperBound])
            let isWordBefore = !before.first.map { $0.isLetter || $0.isNumber || $0 == "_" }!
            let isWordAfter = !after.first.map { $0.isLetter || $0.isNumber || $0 == "_" }!
            if isWordBefore && isWordAfter { return true }
            searchStart = range.upperBound
        }
        return false
    }
}
