import DuckDB
import Foundation

/// 真实实现。连接以只读方式使用，任何写语句在进入引擎前被拦下。
public final class DuckDBSession: QuerySession, @unchecked Sendable {
    public let columns: [ColumnInfo]
    public let rowCount: Int

    private let viewName = "data"
    private var database: Database?
    private var connection: Connection?
    private let lock = NSLock()
    private var closed = false

    private init(database: Database, connection: Connection, columns: [ColumnInfo], rowCount: Int) {
        self.database = database
        self.connection = connection
        self.columns = columns
        self.rowCount = rowCount
    }

    deinit {
        close()
    }

    public static func open(url: URL, format: CSVFormat) throws -> DuckDBSession {
        do {
            let database = try Database(store: .inMemory)
            let connection = try database.connect()

            let path = url.path.replacingOccurrences(of: "'", with: "''")
            let delimiter = format.delimiter == "\t" ? "\t" : String(format.delimiter)
            let delimiterLiteral = delimiter.replacingOccurrences(of: "'", with: "''")
            let header = format.hasHeader ? "true" : "false"

            let createView = """
            CREATE VIEW "data" AS
            SELECT * FROM read_csv_auto('\(path)', delim='\(delimiterLiteral)', header=\(header), auto_detect=true)
            """
            try connection.execute(createView)

            let described = try connection.query("DESCRIBE SELECT * FROM \"data\"")
            let nameColumn = described.column(at: 0).cast(to: String.self)
            let typeColumn = described.column(at: 1).cast(to: String.self)
            let describeCount = Int(described.rowCount)

            let rawNames: [String] = (0..<describeCount).map { index in
                nameColumn[DBInt(index)] ?? "column_\(index + 1)"
            }
            let displayNames = CSVSniffer.sanitizeColumnNames(rawNames)

            var columns: [ColumnInfo] = []
            columns.reserveCapacity(describeCount)
            for index in 0..<describeCount {
                let typeName = typeColumn[DBInt(index)] ?? "VARCHAR"
                columns.append(
                    ColumnInfo(
                        name: rawNames[index],
                        displayName: displayNames[index],
                        typeName: typeName,
                        kind: ColumnKind.infer(fromTypeName: typeName)
                    )
                )
            }

            let counted = try connection.query("SELECT count(*) FROM \"data\"")
            let total = counted.column(at: 0).cast(to: Int64.self)[0] ?? 0

            return DuckDBSession(
                database: database,
                connection: connection,
                columns: columns,
                rowCount: Int(total)
            )
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError.wrap(error, step: "打开文件")
        }
    }

    public func block(offset: Int, size: Int) throws -> TableBlock {
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
        let selectList = columns
            .map { "CAST(\(Self.quoteIdentifier($0.name)) AS VARCHAR)" }
            .joined(separator: ", ")
        let sql = "SELECT \(selectList) FROM \"data\" LIMIT \(safeSize) OFFSET \(safeOffset)"

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
