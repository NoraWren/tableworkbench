import Foundation
import Combine
import DuckDBKit

@MainActor
public final class WorkspaceModel: ObservableObject {
    /// 表到这个行数才值得先出排序首屏，见 R-DEC-23 的后续。
    static let previewRowThreshold = 500_000
    /// 每个文件最新的排序/筛选请求。连点列头时只留最后一个。
    private var desiredViews: [UUID: QueryView] = [:]
    /// 正在跑 worker 的文件，保证同一个条目同时只有一条查询在物化。
    private var applyingEntries: Set<UUID> = []

    public let sqlHistory = SQLHistoryStore()

    public struct RowField: Identifiable, Sendable {
        public let id = UUID()
        public let name: String
        public let value: String?

        public init(name: String, value: String?) {
            self.name = name
            self.value = value
        }
    }

    public struct RowDetail: Identifiable, Sendable {
        public let id = UUID()
        public let row: Int
        public let fields: [RowField]

        public init(row: Int, fields: [RowField]) {
            self.row = row
            self.fields = fields
        }

        /// 两列 TSV：列名、值。空值写成空串，方便直接贴进表格。
        public var tsv: String {
            fields.map { field in
                "\(field.name)\t\(field.value ?? "")"
            }.joined(separator: "\n")
        }
    }
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
        /// 排序或筛选还没算完时先显示的首屏。有它的时候网格只看这几千行，
        /// 总行数仍在算，界面上要说清楚这一点。
        public var preview: TableBlock?

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
            // 换文件时把挂在上一份数据上的展示态一起清掉，
            // 否则中栏会留着上一份的图表或查询结果。
            resetPresentation()
        }
    }
    @Published public private(set) var error: ImportError?
    @Published public private(set) var isLoading = false
    @Published public private(set) var isQuerying = false
    @Published public private(set) var sqlResult: SQLResult?
    /// 透视结果带多层表头，SQL 抽屉的普通查询为 nil，网格按单层画。
    @Published public private(set) var pivotHeader: PivotHeader?
    @Published public private(set) var resultTitle: String?
    @Published public private(set) var isRunningSQL = false
    /// 用户点过取消、但查询还没返回的标记。查询以错误返回时靠它区分「取消」和「真出错」。
    private var cancelRequested = false
    /// 取消后给界面的一句提示，正常流程不显示。
    @Published public private(set) var cancelledMessage: String?
    @Published public private(set) var columnStats: ColumnStats?
    @Published public private(set) var statsColumn: String?
    @Published public private(set) var isLoadingStats = false
    @Published public private(set) var isExporting = false
    @Published public private(set) var lastExportMessage: String?
    /// 网格里当前选中的行，导出“选中行”时用。
    @Published public private(set) var selectedRows: IndexSet = []
    @Published public private(set) var rowDetail: RowDetail?
    @Published public private(set) var chartData: ChartData?
    @Published public private(set) var isBuildingChart = false
    @Published public private(set) var autoCharts: [ChartData]?
    @Published public private(set) var isAnalyzing = false
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
        let requests = urls.map { ($0, urls.count == 1 ? sheetName : nil) }
        open(requests: requests)
    }

    /// 把一个工作簿里的多个工作表一次全部打开，每个工作表单独一条。
    public func open(url: URL, sheetNames: [String]) {
        // 工作表很多时逐个转换很慢，先让用户单选，避免一点就卡住几分钟。
        guard sheetNames.count <= 20 else {
            error = ImportError(
                userMessage: "工作表太多了",
                technicalDetail: "共 \(sheetNames.count) 个",
                recoverySuggestion: "先单独打开需要的那一个，或者用 Excel 拆成几个文件。"
            )
            return
        }
        let requests = sheetNames.map { (url, Optional($0)) }
        open(requests: requests)
    }

    private func open(requests: [(URL, String?)]) {
        guard !requests.isEmpty else { return }
        isLoading = true
        error = nil

        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (files: [OpenedFile], error: ImportError?) in
                var files: [OpenedFile] = []
                var firstError: ImportError?
                for (url, sheet) in requests {
                    do {
                        files.append(try FileImporter.open(url: url, sheetName: sheet))
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
            OpenTiming.mark("会话就绪")
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
        let entryID = entries[index].id
        // 连点列头时只保留最后一次：正在跑的那次照常跑完（duckdb-swift 没有可用的中断接口，
        // 底层的 duckdb_interrupt 在包内 target 里），中间排队的那些直接丢掉，
        // 不用把每一次排序都老老实实物化一遍。
        desiredViews[entryID] = view
        isQuerying = true
        guard !applyingEntries.contains(entryID) else { return }
        applyingEntries.insert(entryID)

        Task {
            while let nextView = desiredViews[entryID] {
                desiredViews[entryID] = nil
                await performApply(view: nextView, entryID: entryID)
            }
            applyingEntries.remove(entryID)
            isQuerying = false
        }
    }

    /// 真正执行一次排序或筛选。连点期间更新的请求由 worker 循环接着做。
    private func performApply(view: QueryView, entryID: UUID) async {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        let session = entries[index].session
        let columns = session.displayColumns
        // 小表物化本来就是几十毫秒，先出预览只会让界面闪一下，所以只在够大的表上做。
        let wantsPreview = entries[index].rowCount >= WorkspaceModel.previewRowThreshold
            && (!view.sort.isEmpty || view.filter != nil)

        if wantsPreview {
            OpenTiming.mark("首屏预览开始")
            let preview = await Task.detached(priority: .userInitiated) { () -> TableBlock? in
                (try? session.previewBlock(view: view, columns: columns, limit: QuerySessionDefaults.blockSize)) ?? nil
            }.value
            // 预览回来时如果已经有更新的请求在排队，就别拿旧结果再占一次界面。
            if let preview, desiredViews[entryID] == nil,
               let current = entries.firstIndex(where: { $0.id == entryID }) {
                entries[current].preview = preview
                OpenTiming.mark("首屏预览就绪 \(preview.rows.count) 行")
            }
        }

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
                // 全量结果就绪，预览态收掉，网格按新的 queryVersion 重建。
                entries[current].preview = nil
                entries[current].queryVersion += 1
            }
        } else {
            if let current = entries.firstIndex(where: { $0.id == entryID }) {
                entries[current].preview = nil
            }
            if cancelRequested {
                // 用户自己取消的，不弹错误卡片，只留一句已取消。
                cancelledMessage = "已取消"
            } else {
                error = outcome.error
            }
        }
    }

    public func runSQL(entryID: UUID, sql: String) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let session = entries[index].session
        isRunningSQL = true
        cancelRequested = false
        cancelledMessage = nil
        sqlResult = nil
        // 普通查询没有维度概念，表头回到单层。
        pivotHeader = nil
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

            // 文件可能在查询期间被关掉，这时结果没有归处，直接丢弃。
            guard isOpen(entryID) else { return }
            if let result = outcome.0 {
                sqlResult = result
                sqlHistory.record(trimmed)
            } else if cancelRequested {
                // 用户自己取消的，不该弹错误卡片。
                cancelledMessage = "已取消"
            } else {
                error = outcome.1
            }
            isRunningSQL = false
        }
    }

    /// 取消当前正在跑的查询或物化。中断通过 duckdb_interrupt 下达，
    /// 查询会以错误返回，由上面的 cancelRequested 分支吞掉错误换成「已取消」。
    public func cancelCurrentQuery() {
        guard let entry = selectedEntry else { return }
        cancelRequested = true
        entry.session.interrupt()
    }

    public func runPivot(entryID: UUID, spec: PivotSpec) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }), spec.isValid else { return }
        let session = entries[index].session
        isRunningSQL = true
        sqlResult = nil
        pivotHeader = nil
        resultTitle = "透视结果"
        error = nil

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (PivotResult?, ImportError?) in
                do {
                    return (try session.pivotWithHeader(spec: spec), nil)
                } catch let importError as ImportError {
                    return (nil, importError)
                } catch {
                    return (nil, ImportError.wrap(error, step: "执行透视"))
                }
            }.value

            guard isOpen(entryID) else { return }
            if let result = outcome.0 {
                sqlResult = result.result
                pivotHeader = result.header
            } else {
                error = outcome.1
            }
            isRunningSQL = false
        }
    }

    /// 分组建图：复用透视的单维度查询，再把结果整理成图上的点。
    public func runChart(entryID: UUID, spec: ChartSpec) {
        guard spec.isValid, let entry = entries.first(where: { $0.id == entryID }) else { return }
        let session = entry.session
        isBuildingChart = true
        chartData = nil
        // 上一次的失败提示留着会盖在新图上。
        error = nil

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (ChartData?, ImportError?) in
                do {
                    let result = try session.pivot(spec: spec.pivotSpec)
                    return (ChartData.build(result: result, spec: spec), nil)
                } catch let importError as ImportError {
                    return (nil, importError)
                } catch {
                    return (nil, ImportError.wrap(error, step: "生成图表"))
                }
            }.value

            guard isOpen(entryID) else { return }
            if let data = outcome.0 {
                chartData = data
            } else {
                error = outcome.1
            }
            isBuildingChart = false
        }
    }

    public func clearChart() {
        chartData = nil
    }

    /// 一键分析：自己挑分组列与度量列，连着生成几张柱状图。
    public func runAutoAnalysis(entryID: UUID) {
        guard let entry = entries.first(where: { $0.id == entryID }) else { return }
        let session = entry.session
        let columns = entry.columns
        isAnalyzing = true
        autoCharts = nil
        error = nil

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> ([ChartData], ImportError?) in
                let specs = AutoAnalysis.plan(columns: columns) { name in
                    (try? session.distinctCount(column: name)) ?? Int.max
                }
                guard !specs.isEmpty else {
                    let hasNumeric = columns.contains { $0.kind.isNumeric }
                    return ([], ImportError(
                        userMessage: hasNumeric ? "没有可以分组的列" : "没有数值列",
                        technicalDetail: nil,
                        recoverySuggestion: hasNumeric
                            ? "表格里需要一个取值不多的文本列，比如区域、状态。"
                            : "先用计算列造一个数值列，再试一键分析。"
                    ))
                }
                var charts: [ChartData] = []
                for spec in specs {
                    do {
                        let result = try session.pivot(spec: spec.pivotSpec)
                        charts.append(ChartData.build(result: result, spec: spec))
                    } catch {
                        // 单张图失败不影响其余的，最后统一报错。
                        return (charts, ImportError.wrap(error, step: "一键分析"))
                    }
                }
                return (charts, nil)
            }.value

            guard isOpen(entryID) else { return }
            autoCharts = outcome.0.isEmpty ? nil : outcome.0
            error = outcome.1
            isAnalyzing = false
        }
    }

    public func clearAutoAnalysis() {
        autoCharts = nil
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

    public func updateSelectedRows(_ rows: IndexSet) {
        guard rows != selectedRows else { return }
        selectedRows = rows
    }

    /// 双击一行后取这一行的全部显示列，宽表只取裁剪后的列。
    public func loadRowDetail(entryID: UUID, row: Int) {
        guard let entry = entries.first(where: { $0.id == entryID }) else { return }
        let session = entry.session
        let columns = shownColumns(for: entry)
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> ([String?]?, ImportError?) in
                do {
                    let block = try session.block(offset: row, size: 1, columns: columns)
                    return (block.rows.first, nil)
                } catch let importError as ImportError {
                    return (nil, importError)
                } catch {
                    return (nil, ImportError.wrap(error, step: "读取行"))
                }
            }.value

            if let values = outcome.0 {
                let fields = zip(columns, values).map { column, value in
                    RowField(name: column.displayName, value: value)
                }
                rowDetail = RowDetail(row: row, fields: fields)
            } else {
                error = outcome.1
            }
        }
    }

    public func dismissRowDetail() {
        rowDetail = nil
    }

    public func export(entryID: UUID, to url: URL, format: ExportFormat, scope: ExportScope = .view) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        let session = entries[index].session
        isExporting = true
        lastExportMessage = nil
        cancelRequested = false
        cancelledMessage = nil

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (Int?, ImportError?) in
                do {
                    return (try session.export(to: url, format: format, scope: scope), nil)
                } catch let importError as ImportError {
                    return (nil, importError)
                } catch {
                    return (nil, ImportError.wrap(error, step: "导出"))
                }
            }.value

            if let count = outcome.0 {
                let scopeName: String
                switch scope {
                case .view: scopeName = "当前视图"
                case .all: scopeName = "全部行"
                case .rows: scopeName = "选中行"
                }
                lastExportMessage = "已导出\(scopeName) \(count) 行到 \(url.lastPathComponent)"
            } else {
                if cancelRequested {
                    // 取消导出：临时文件已由会话层删掉，目标位置不会留半截文件。
                    cancelledMessage = "已取消导出"
                } else {
                    error = outcome.1
                }
            }
            isExporting = false
        }
    }

    public func clearSQLResult() {
        sqlResult = nil
        pivotHeader = nil
        resultTitle = nil
    }

    /// 把透视配置翻译成 SQL 交给界面，用户可以在 SQL 抽屉里改着用。
    /// 生成和执行是同一份拼装逻辑，复现出来的结果与透视结果一致。
    public func makePivotSQL(entryID: UUID, spec: PivotSpec, completion: @escaping @MainActor (String?) -> Void) {
        guard let entry = entries.first(where: { $0.id == entryID }) else {
            completion(nil)
            return
        }
        let session = entry.session
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (String?, ImportError?) in
                do {
                    return (try session.pivotSQL(spec: spec), nil)
                } catch let importError as ImportError {
                    return (nil, importError)
                } catch {
                    return (nil, ImportError.wrap(error, step: "生成透视 SQL"))
                }
            }.value

            if let sql = outcome.0 {
                completion(sql)
            } else {
                error = outcome.1
                completion(nil)
            }
        }
    }

    public func closeSelected() {
        guard let selection, let index = entries.firstIndex(where: { $0.id == selection }) else { return }
        // 先清展示态再关连接：反过来的话，改 selection 触发的重绘
        // 有一帧可能去读一个已经关掉的会话。
        resetPresentation()
        entries[index].session.close()
        entries.remove(at: index)
        self.selection = entries.first?.id
    }

    /// 清掉所有挂在当前文件上的展示态。切文件与关文件都走这里，
    /// 以后新增一类结果只需要在这一个地方登记。
    private func resetPresentation() {
        statsColumn = nil
        columnStats = nil
        isLoadingStats = false
        selectedRows = []
        rowDetail = nil
        chartData = nil
        isBuildingChart = false
        autoCharts = nil
        isAnalyzing = false
        sqlResult = nil
        pivotHeader = nil
        resultTitle = nil
        isRunningSQL = false
    }

    /// 异步任务回来时用它确认目标文件还开着。
    private func isOpen(_ entryID: UUID) -> Bool {
        entries.contains { $0.id == entryID }
    }

    public func report(_ error: ImportError) {
        self.error = error
    }

    public func dismissError() {
        error = nil
    }
}
