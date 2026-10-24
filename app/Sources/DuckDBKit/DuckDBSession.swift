import DuckDB
import Foundation

/// 真实实现。连接以只读方式使用，任何写语句在进入引擎前被拦下。
public final class DuckDBSession: QuerySession, @unchecked Sendable {
    public let columns: [ColumnInfo]
    public let rowCount: Int
    public private(set) var resultCount: Int
    public private(set) var generation: Int = 0
    private var view: QueryView = .empty
    private var hasResultTable = false
    private var computedColumns: [(name: String, expression: String)] = []
    /// 按列缓存统计，配 generation 判断是否失效。
    private var statsCache: [String: (generation: Int, stats: ColumnStats)] = [:]
    private var database: Database?
    private var connection: Connection?
    private let temporaryDirectory: URL
    private let lock = NSLock()
    private var closed = false

    private init(database: Database, connection: Connection, temporaryDirectory: URL, columns: [ColumnInfo], rowCount: Int) {
        self.database = database
        self.connection = connection
        self.temporaryDirectory = temporaryDirectory
        self.columns = columns
        self.rowCount = rowCount
        self.resultCount = rowCount
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

    private static func open(source: Source) throws -> DuckDBSession {
        do {
            let fileManager = FileManager.default
            let temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent("tableworkbench-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            let database = try Database(store: .inMemory)
            let connection = try database.connect()
            try connection.execute("SET memory_limit='1200MB'")
            try connection.execute("SET temp_directory='\(temporaryDirectory.path.replacingOccurrences(of: "'", with: "''"))'")

            let createTable: String
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
                createTable = "CREATE TABLE \"__base\" AS SELECT * FROM read_parquet('\(path)')"
            }
            try connection.execute(createTable)
            try connection.execute("CREATE VIEW \"data\" AS SELECT * FROM \"__base\"")

            let described = try connection.query("DESCRIBE SELECT * FROM \"__base\"")
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

            return DuckDBSession(
                database: database,
                connection: connection,
                temporaryDirectory: temporaryDirectory,
                columns: columns,
                rowCount: Int(total)
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
                try connection.execute(createResult)
                hasResultTable = true
                let counted = try connection.query("SELECT count(*) FROM \"__result\"")
                resultCount = Int(counted.column(at: 0).cast(to: Int64.self)[0] ?? 0)
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

        do {
            var aggregateSelect = """
            SELECT count(*), count(\(identifier)), count(DISTINCT \(identifier)),
                   CAST(min(\(identifier)) AS VARCHAR), CAST(max(\(identifier)) AS VARCHAR),
                   avg(\(numeric)), median(\(numeric)), stddev_pop(\(numeric))
            """
            if info.kind == .text {
                aggregateSelect += ",\n                   min(length(\(identifier))), max(length(\(identifier))),\n                   count(*) FILTER (WHERE \(identifier) <> trim(\(identifier)))"
            }
            aggregateSelect += "\nFROM \(table)"
            let aggregate = try connection.query(aggregateSelect)
            let total = Int(aggregate.column(at: 0).cast(to: Int64.self)[0] ?? 0)
            let nonNull = Int(aggregate.column(at: 1).cast(to: Int64.self)[0] ?? 0)
            let distinct = Int(aggregate.column(at: 2).cast(to: Int64.self)[0] ?? 0)
            let minValue = aggregate.column(at: 3).cast(to: String.self)[0]
            let maxValue = aggregate.column(at: 4).cast(to: String.self)[0]
            let mean = aggregate.column(at: 5).cast(to: Double.self)[0]
            let median = aggregate.column(at: 6).cast(to: Double.self)[0]
            let deviation = aggregate.column(at: 7).cast(to: Double.self)[0]
            let minLength = info.kind == .text ? Int(aggregate.column(at: 8).cast(to: Int64.self)[0] ?? 0) : nil
            let maxLength = info.kind == .text ? Int(aggregate.column(at: 9).cast(to: Int64.self)[0] ?? 0) : nil
            let whitespaceCount = info.kind == .text ? Int(aggregate.column(at: 10).cast(to: Int64.self)[0] ?? 0) : nil

            var topValues: [TopValue] = []
            let top = try connection.query("""
            SELECT CAST(\(identifier) AS VARCHAR) AS v, count(*) AS c
            FROM \(table) WHERE \(identifier) IS NOT NULL
            GROUP BY 1 ORDER BY 2 DESC, 1 ASC LIMIT 10
            """)
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
                let bucketQuery = try connection.query("""
                SELECT least(19, greatest(0, CAST(floor((\(numeric) - \(lower)) / \(step)) AS INTEGER))) AS b, count(*)
                FROM \(table) WHERE \(identifier) IS NOT NULL AND \(numeric) IS NOT NULL
                GROUP BY b ORDER BY b
                """)
                var counts = Array(repeating: 0, count: 20)
                let bucketColumn = bucketQuery.column(at: 0).cast(to: Int64.self)
                let countColumn = bucketQuery.column(at: 1).cast(to: Int64.self)
                for index in 0..<Int(bucketQuery.rowCount) {
                    let bucket = Int(bucketColumn[DBInt(index)] ?? 0)
                    let count = Int(countColumn[DBInt(index)] ?? 0)
                    let clamped = min(19, max(0, bucket - 1))
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
            if info.kind == .text, nonNull > 0 {
                let numericQuery = try connection.query("""
                SELECT count(*) FROM \(table)
                WHERE \(identifier) IS NOT NULL AND TRY_CAST(\(identifier) AS DOUBLE) IS NOT NULL
                """)
                numericCount = Int(numericQuery.column(at: 0).cast(to: Int64.self)[0] ?? 0)
                if numericCount > 0 && numericCount < nonNull {
                    let examples = try connection.query("""
                    SELECT CAST(\(identifier) AS VARCHAR) FROM \(table)
                    WHERE \(identifier) IS NOT NULL AND TRY_CAST(\(identifier) AS DOUBLE) IS NULL
                    LIMIT 2
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
                let timeQuery = try connection.query("""
                SELECT CAST(date_trunc('day', CAST(\(identifier) AS TIMESTAMP)) AS VARCHAR) AS d, count(*)
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
        lock.lock()
        defer { lock.unlock() }

        guard !closed, let connection else {
            throw ImportError(userMessage: "数据源已关闭", technicalDetail: nil, recoverySuggestion: "重新打开文件。")
        }

        let table = hasResultTable ? "\"__result\"" : "\"__base\""
        let columnsSQL = SQLBuilder.columnList(columns)
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
        let sql = "COPY (SELECT \(columnsSQL) FROM \(table)) TO '\(destination)' (\(options))"

        do {
            try connection.execute(sql)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: temporary, to: url)
            return resultCount
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw ImportError(
                userMessage: "导出失败",
                technicalDetail: String(describing: error),
                recoverySuggestion: "确认目标目录有写权限，换一个位置再试。"
            )
        }
    }

    public func pivot(spec: PivotSpec) throws -> SQLResult {
        lock.lock()
        defer { lock.unlock() }

        guard !closed, let connection else {
            throw ImportError(userMessage: "数据源已关闭", technicalDetail: nil, recoverySuggestion: "重新打开文件。")
        }
        guard spec.isValid else {
            throw ImportError(
                userMessage: "透视配置不完整",
                technicalDetail: "至少需要一个行字段和一个值字段",
                recoverySuggestion: "把字段拖到行和值区域。"
            )
        }

        let known = Set(columns.map(\.name))
        let allFields = spec.rows + spec.columns + spec.values.map(\.column)
        for field in allFields where !known.contains(field) {
            throw ImportError(userMessage: "字段不存在", technicalDetail: field, recoverySuggestion: "重新选择字段。")
        }

        let table = hasResultTable ? "\"__result\"" : "\"__base\""
        let rowSQL = spec.rows.map(pivotLabel).joined(separator: ", ")
        let rowAliases = spec.rows.map(SQLBuilder.quoteIdentifier).joined(separator: ", ")
        let rowSelect = spec.rows
            .map { "\(pivotLabel($0)) AS \(SQLBuilder.quoteIdentifier($0))" }
            .joined(separator: ", ")
        let started = Foundation.Date()

        do {
            let distinctRows = try connection.query(
                "SELECT count(*) FROM (SELECT DISTINCT \(rowSQL) FROM \(table)) AS t"
            )
            let rowCount = Int(distinctRows.column(at: 0).cast(to: Int64.self)[0] ?? 0)
            guard rowCount <= 5000 else {
                throw ImportError(
                    userMessage: "行维度太多了",
                    technicalDetail: "去重后有 \(rowCount) 行，上限 5000",
                    recoverySuggestion: "换一个基数更低的字段，或先加筛选。"
                )
            }

            var selectParts = [rowSelect]
            if spec.columns.isEmpty {
                for value in spec.values {
                    selectParts.append("\(aggregateSQL(value, condition: nil)) AS \(SQLBuilder.quoteIdentifier(value.title))")
                }
            } else {
                let columnSQL = spec.columns.map { "\(pivotLabel($0)) AS \(SQLBuilder.quoteIdentifier($0))" }
                    .joined(separator: ", ")
                let combosResult = try connection.query(
                    "SELECT DISTINCT \(columnSQL) FROM \(table) LIMIT 201"
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
                var combos: [[String]] = []
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

            let sql = "SELECT \(selectParts.joined(separator: ", ")) FROM \(table) GROUP BY \(rowSQL) ORDER BY \(rowAliases)"
            return try executeSelect(sql, connection: connection, started: started)
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
        if applyLimit {
            let described = try connection.query("DESCRIBE \(statement)")
            let nameColumn = described.column(at: 0).cast(to: String.self)
            for index in 0..<Int(described.rowCount) {
                columnNames.append(nameColumn[DBInt(index)] ?? "column_\(index + 1)")
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
            columns.append(ColumnInfo(name: name, displayName: name, typeName: "VARCHAR", kind: .text))
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
        var selectParts: [String] = []
        selectParts.reserveCapacity(requested.count)
        for info in requested {
            if info.isComputed {
                if let computed = computedColumns.first(where: { $0.name == info.name }) {
                    selectParts.append("CAST((\(computed.expression)) AS VARCHAR) AS \(SQLBuilder.quoteIdentifier(computed.name))")
                }
            } else {
                selectParts.append(SQLBuilder.selectList([info]))
            }
        }
        if selectParts.isEmpty {
            return TableBlock(offset: safeOffset, rows: [])
        }
        let selectList = selectParts.joined(separator: ", ")
        let table = hasResultTable ? "\"__result\"" : "\"__base\""
        let upperBound = safeOffset + safeSize
        let sql = "SELECT \(selectList) FROM \(table) WHERE rowid >= \(safeOffset) AND rowid < \(upperBound) ORDER BY rowid"

        do {
            let result = try connection.query(sql)
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
            return TableBlock(offset: safeOffset, rows: rows)
        } catch {
            throw ImportError.wrap(error, step: "读取数据")
        }
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
