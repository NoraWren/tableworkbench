import Foundation
import Combine
import DuckDBKit

@MainActor
public final class WorkspaceModel: ObservableObject {
    public let sqlHistory = SQLHistoryStore()
    public struct Entry: Identifiable {
        public let id: UUID
        public let url: URL
        public let session: QuerySession
        public let encoding: TextEncoding
        public let sheetName: String?
        public var sort: [SortSpec] = []
        public var filter: FilterGroup?
        public var resultCount: Int
        public var queryVersion: Int = 0

        public init(
            id: UUID = UUID(),
            url: URL,
            session: QuerySession,
            encoding: TextEncoding,
            sheetName: String? = nil
        ) {
            self.id = id
            self.url = url
            self.session = session
            self.encoding = encoding
            self.sheetName = sheetName
            self.resultCount = session.rowCount
        }

        public var displayName: String {
            url.lastPathComponent + (sheetName.map { " · \($0)" } ?? "")
        }
        public var rowCount: Int { session.rowCount }
        public var columns: [ColumnInfo] { session.columns }
        public var displayColumns: [ColumnInfo] { session.displayColumns }
    }

    @Published public private(set) var entries: [Entry] = []
    @Published public var selection: UUID? {
        didSet {
            guard oldValue != selection else { return }
            // 换文件时清掉上一份的列统计，别让检查器张冠李戴。
            statsColumn = nil
            columnStats = nil
            isLoadingStats = false
        }
    }
    @Published public private(set) var error: ImportError?
    @Published public private(set) var isLoading = false
    @Published public private(set) var isQuerying = false
    @Published public private(set) var sqlResult: SQLResult?
    @Published public private(set) var resultTitle: String?
    @Published public private(set) var isRunningSQL = false
    @Published public private(set) var columnStats: ColumnStats?
    @Published public private(set) var statsColumn: String?
    @Published public private(set) var isLoadingStats = false
    @Published public private(set) var isExporting = false
    @Published public private(set) var lastExportMessage: String?
    /// 宽表里用户手动启用的列，按文件记。默认只显示前 200 列。
    @Published private var enabledColumns: [UUID: Set<String>] = [:]

    public init() {}

    public var selectedEntry: Entry? {
        guard let selection else { return nil }
        return entries.first { $0.id == selection }
    }

    /// 表格实际显示的列。普通表原样返回，宽表按启用集合裁剪。
    public func shownColumns(for entry: Entry) -> [ColumnInfo] {
        ColumnVisibility.shown(entry.displayColumns, enabled: enabledColumns[entry.id])
    }

    public func isColumnShown(entryID: UUID, column: String) -> Bool {
        guard let entry = entries.first(where: { $0.id == entryID }) else { return false }
        return shownColumns(for: entry).contains { $0.name == column }
    }

    public func toggleColumn(entryID: UUID, column: String) {
        guard let entry = entries.first(where: { $0.id == entryID }) else { return }
        enabledColumns[entryID] = ColumnVisibility.toggled(
            entry.displayColumns,
            enabled: enabledColumns[entryID],
            column: column
        )
    }

    public func open(urls: [URL], sheetName: String? = nil) {
        guard !urls.isEmpty else { return }
        isLoading = true
        error = nil

        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (files: [OpenedFile], error: ImportError?) in
                var files: [OpenedFile] = []
                var firstError: ImportError?
                for url in urls {
                    do {
                        files.append(try FileImporter.open(url: url, sheetName: urls.count == 1 ? sheetName : nil))
                    } catch let importError as ImportError {
                        if firstError == nil { firstError = importError }
                    } catch {
                        if firstError == nil { firstError = ImportError.wrap(error, step: "打开文件") }
                    }
                }
                return (files, firstError)
            }.value

            var firstAdded: UUID?
            for file in result.files {
                if let existing = entries.first(where: {
                    $0.url == file.url && $0.sheetName == file.sheetName
                }) {
                    file.session.close()
                    selection = existing.id
                    continue
                }

                let entry = Entry(
                    url: file.url,
                    session: file.session,
                    encoding: file.encoding,
                    sheetName: file.sheetName
                )
                entries.append(entry)
                if firstAdded == nil { firstAdded = entry.id }
            }
            // 刚打开的文件直接选中，别让用户以为没反应。
            if let firstAdded {
                selection = firstAdded
            }
            error = result.error
            isLoading = false
        }
    }

    public func toggleSort(entryID: UUID, column: String, additive: Bool) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        var sorts = entries[index].sort

        if additive {
            if let position = sorts.firstIndex(where: { $0.column == column }) {
                if sorts[position].ascending {
                    sorts[position] = SortSpec(column: column, ascending: false)
                } else {
                    sorts.remove(at: position)
                }
            } else {
                sorts.append(SortSpec(column: column, ascending: true))
            }
        } else {
            if sorts.count == 1, sorts[0].column == column {
                sorts = sorts[0].ascending
                    ? [SortSpec(column: column, ascending: false)]
                    : []
            } else {
                sorts = [SortSpec(column: column, ascending: true)]
            }
        }

        apply(view: QueryView(sort: sorts, filter: entries[index].filter), to: index)
    }

    public func applyFilter(entryID: UUID, filter: FilterGroup?) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        apply(view: QueryView(sort: entries[index].sort, filter: filter), to: index)
    }

    private func apply(view: QueryView, to index: Int) {
        let session = entries[index].session
        let entryID = entries[index].id
        isQuerying = true

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (count: Int?, error: ImportError?) in
                do {
                    try session.apply(view: view)
                    return (session.resultCount, nil)
                } catch let importError as ImportError {
                    return (nil, importError)
                } catch {
                    return (nil, ImportError.wrap(error, step: "执行查询"))
                }
            }.value

            if let count = outcome.count {
                // 查询期间可能关掉或打开别的文件，按 id 重新定位，别写错行。
                if let current = entries.firstIndex(where: { $0.id == entryID }) {
                    entries[current].sort = view.sort
                    entries[current].filter = view.filter
                    entries[current].resultCount = count
                    entries[current].queryVersion += 1
                }
            } else {
                error = outcome.error
            }
            isQuerying = false
        }
    }

    public func runSQL(entryID: UUID, sql: String) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let session = entries[index].session
        isRunningSQL = true
        sqlResult = nil
        resultTitle = "查询结果"

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (SQLResult?, ImportError?) in
                do {
                    return (try session.runSQL(trimmed), nil)
                } catch let importError as ImportError {
                    return (nil, importError)
                } catch {
                    return (nil, ImportError.wrap(error, step: "执行 SQL"))
                }
            }.value

            if let result = outcome.0 {
                sqlResult = result
                sqlHistory.record(trimmed)
            } else {
                error = outcome.1
            }
            isRunningSQL = false
        }
    }

    public func runPivot(entryID: UUID, spec: PivotSpec) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }), spec.isValid else { return }
        let session = entries[index].session
        isRunningSQL = true
        sqlResult = nil
        resultTitle = "透视结果"

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (SQLResult?, ImportError?) in
                do {
                    return (try session.pivot(spec: spec), nil)
                } catch let importError as ImportError {
                    return (nil, importError)
                } catch {
                    return (nil, ImportError.wrap(error, step: "执行透视"))
                }
            }.value

            if let result = outcome.0 {
                sqlResult = result
            } else {
                error = outcome.1
            }
            isRunningSQL = false
        }
    }

    public func addComputedColumn(entryID: UUID, name: String, expression: String) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        let session = entries[index].session
        let targetID = entryID

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> ImportError? in
                do {
                    try session.addComputedColumn(name: name, expression: expression)
                    return nil
                } catch let importError as ImportError {
                    return importError
                } catch {
                    return ImportError.wrap(error, step: "添加计算列")
                }
            }.value

            if let outcome {
                error = outcome
            } else {
                if let current = entries.firstIndex(where: { $0.id == targetID }) {
                    entries[current].queryVersion += 1
                }
            }
        }
    }

    public func loadStats(entryID: UUID, column: String) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        let session = entries[index].session
        statsColumn = column
        columnStats = nil
        isLoadingStats = true

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (ColumnStats?, ImportError?) in
                do {
                    return (try session.columnStats(column: column), nil)
                } catch let importError as ImportError {
                    return (nil, importError)
                } catch {
                    return (nil, ImportError.wrap(error, step: "统计列"))
                }
            }.value

            if statsColumn == column, selection == entryID {
                if let stats = outcome.0 {
                    columnStats = stats
                } else {
                    error = outcome.1
                }
                isLoadingStats = false
            }
        }
    }

    public func export(entryID: UUID, to url: URL, format: ExportFormat) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        let session = entries[index].session
        isExporting = true
        lastExportMessage = nil

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (Int?, ImportError?) in
                do {
                    return (try session.export(to: url, format: format), nil)
                } catch let importError as ImportError {
                    return (nil, importError)
                } catch {
                    return (nil, ImportError.wrap(error, step: "导出"))
                }
            }.value

            if let count = outcome.0 {
                lastExportMessage = "已导出 \(count) 行到 \(url.lastPathComponent)"
            } else {
                error = outcome.1
            }
            isExporting = false
        }
    }

    public func clearSQLResult() {
        sqlResult = nil
        resultTitle = nil
    }

    public func closeSelected() {
        guard let selection, let index = entries.firstIndex(where: { $0.id == selection }) else { return }
        entries[index].session.close()
        entries.remove(at: index)
        self.selection = entries.first?.id
    }

    public func report(_ error: ImportError) {
        self.error = error
    }

    public func dismissError() {
        error = nil
    }
}
