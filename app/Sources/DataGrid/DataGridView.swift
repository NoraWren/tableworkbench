import SwiftUI
import AppKit
import DuckDBKit

/// 固定在左侧的行号条，不参与横向滚动，纵向跟随主表的可见行。
final class RowNumbersView: NSView {
    private weak var tableView: NSTableView?
    private weak var scrollView: NSScrollView?

    override var isFlipped: Bool { true }

    func attach(tableView: NSTableView, scrollView: NSScrollView) {
        self.tableView = tableView
        self.scrollView = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func contentDidScroll() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        guard let tableView, let scrollView else { return }
        let headerHeight = max(24, tableView.headerView?.frame.height ?? 24)
        let clip = scrollView.contentView.bounds
        let rowHeight = tableView.rowHeight + tableView.intercellSpacing.height

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        ("#" as NSString).draw(
            at: NSPoint(x: bounds.width - 22, y: max(0, (headerHeight - 14) / 2)),
            withAttributes: headerAttributes
        )

        let visible = tableView.rows(in: clip)
        if visible.length > 0 {
            for row in visible.location..<(visible.location + visible.length) {
                let rowRect = tableView.rect(ofRow: row)
                let y = rowRect.minY - clip.minY
                let cellRect = NSRect(x: 0, y: y, width: bounds.width - 8, height: max(rowHeight, rowRect.height))
                let text = String(row + 1) as NSString
                let size = text.size(withAttributes: attributes)
                text.draw(
                    at: NSPoint(x: cellRect.maxX - size.width, y: cellRect.midY - size.height / 2),
                    withAttributes: attributes
                )
            }
        }

        NSColor.separatorColor.setFill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: headerHeight - 1, width: bounds.width, height: 1).fill()
    }
}

public struct DataGridView: NSViewRepresentable {
    public static let maxVisibleColumns = QuerySessionDefaults.maxVisibleColumns
    public static let defaultVisibleColumns = QuerySessionDefaults.defaultVisibleColumns
    public static let rowHeaderWidth: CGFloat = 56

    public let columns: [ColumnInfo]
    public let rowCount: Int
    public let sorts: [SortSpec]
    /// 多层表头。传 nil 时按每列一个标题画，和以前一样。
    public let header: PivotHeader?
    public let provider: (Int, Int) throws -> TableBlock
    public let onSortClick: (String, Bool) -> Void
    public let onSelectionChange: (IndexSet) -> Void
    public let onRowActivate: (Int) -> Void
    public let onError: (Error) -> Void

    public init(
        columns: [ColumnInfo],
        rowCount: Int,
        sorts: [SortSpec] = [],
        header: PivotHeader? = nil,
        provider: @escaping (Int, Int) throws -> TableBlock,
        onSortClick: @escaping (String, Bool) -> Void = { _, _ in },
        onSelectionChange: @escaping (IndexSet) -> Void = { _ in },
        onRowActivate: @escaping (Int) -> Void = { _ in },
        onError: @escaping (Error) -> Void
    ) {
        self.columns = columns
        self.rowCount = rowCount
        self.sorts = sorts
        self.header = header
        self.provider = provider
        self.onSortClick = onSortClick
        self.onSelectionChange = onSelectionChange
        self.onRowActivate = onRowActivate
        self.onError = onError
    }

    public func makeCoordinator() -> GridDataSource {
        let dataSource = GridDataSource()
        dataSource.columns = visibleColumns
        dataSource.rowCount = rowCount
        dataSource.provider = provider
        dataSource.onError = onError
        dataSource.onSortClick = onSortClick
        dataSource.onSelectionChange = onSelectionChange
        dataSource.computedColumnNames = Set(columns.filter(\.isComputed).map(\.name))
        return dataSource
    }

    public func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let rowNumbers = RowNumbersView()
        rowNumbers.translatesAutoresizingMaskIntoConstraints = false

        let tableView = GridTableView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowSizeStyle = .medium
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = false
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        // AppKit 在这行就会把行数记进内部结构。先让它按 0 行接上，等视图搭完再用
        // reloadData 带进真实行数，省掉 300 万行在这里的一次性开销。
        let realRowCount = context.coordinator.rowCount
        context.coordinator.rowCount = 0
        tableView.dataSource = context.coordinator
        context.coordinator.rowCount = realRowCount
        tableView.delegate = context.coordinator
        tableView.target = tableView
        tableView.doubleAction = #selector(GridTableView.activateRow(_:))
        tableView.onRowActivate = onRowActivate

        let headerView = GridHeaderView(frame: NSRect(x: 0, y: 0, width: 0, height: 24))
        headerView.header = header
        tableView.headerView = headerView

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // 冻结列盖在滚动区左边，先加滚动区再加它，保证它在上面。
        let frozen = FrozenColumnsView()
        frozen.translatesAutoresizingMaskIntoConstraints = false
        frozen.header = header
        let frozenWidth = frozen.widthAnchor.constraint(equalToConstant: 0)
        frozenWidth.isActive = true
        frozen.widthConstraint = frozenWidth

        container.addSubview(rowNumbers)
        container.addSubview(scrollView)
        container.addSubview(frozen)
        NSLayoutConstraint.activate([
            rowNumbers.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            rowNumbers.topAnchor.constraint(equalTo: container.topAnchor),
            rowNumbers.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rowNumbers.widthAnchor.constraint(equalToConstant: Self.rowHeaderWidth),
            scrollView.leadingAnchor.constraint(equalTo: rowNumbers.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            frozen.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            frozen.topAnchor.constraint(equalTo: container.topAnchor),
            frozen.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        rowNumbers.attach(tableView: tableView, scrollView: scrollView)
        frozen.attach(tableView: tableView, scrollView: scrollView)
        context.coordinator.contentTableView = tableView
        context.coordinator.rowNumbersView = rowNumbers
        context.coordinator.frozenView = frozen
        context.coordinator.scrollView = scrollView
        rebuildColumns(tableView)
        applyHeaderLayout(tableView: tableView, scrollView: scrollView, frozen: frozen)
        return container
    }

    public func updateNSView(_ view: NSView, context: Context) {
        let dataSource = context.coordinator
        dataSource.provider = provider
        dataSource.onError = onError
        dataSource.onSortClick = onSortClick
        dataSource.onSelectionChange = onSelectionChange
        if let tableView = dataSource.contentTableView as? GridTableView {
            tableView.onRowActivate = onRowActivate
        }
        dataSource.computedColumnNames = Set(columns.filter(\.isComputed).map(\.name))

        let changed = dataSource.columns != visibleColumns
            || dataSource.rowCount != rowCount
            || dataSource.sorts != sorts
        dataSource.columns = visibleColumns
        dataSource.rowCount = rowCount
        dataSource.sorts = sorts

        if let tableView = dataSource.contentTableView {
            if changed {
                dataSource.resetFailedBlocks()
                rebuildColumns(tableView)
            }
            applyHeaderLayout(
                tableView: tableView,
                scrollView: dataSource.scrollView,
                frozen: dataSource.frozenView
            )
        }
        dataSource.rowNumbersView?.needsDisplay = true
    }

    /// 把表头层数和冻结列数同步到视图上。层数变了要连表头高度和冻结区宽度一起改，
    /// 否则多出来的那层表头会盖住首行，冻结区还停在上一份结果的位置。
    private func applyHeaderLayout(
        tableView: NSTableView,
        scrollView: NSScrollView?,
        frozen: FrozenColumnsView?
    ) {
        let levels = max(1, header?.levelCount ?? 1)
        let height = GridHeaderView.height(forLevels: levels)
        if let headerView = tableView.headerView as? GridHeaderView {
            // 表的列重建后，表头里的层级要跟着换一份，否则画的是上一次的格子。
            headerView.header = header
            if abs(headerView.frame.height - height) > 0.5 {
                resizeHeader(tableView: tableView, scrollView: scrollView, to: height)
            }
        }

        guard let frozen else { return }
        frozen.header = header
        // 行维度列冻结。至少留一列不冻结，否则结果列宽为零时冻结区会和滚动区打架。
        frozen.frozenColumnCount = min(header?.rowDimensionCount ?? 0, max(0, visibleColumns.count - 1))
        frozen.widthConstraint?.constant = frozen.frozenWidth
        frozen.needsDisplay = true
    }

    /// 改表头高度。AppKit 的自动上内边距不会跟着变，用户停在顶部时得自己把滚动位置补回去，
    /// 否则多出来的那层表头正好压在首行上。
    private func resizeHeader(tableView: NSTableView, scrollView: NSScrollView?, to height: CGFloat) {
        guard let headerView = tableView.headerView, let scrollView else { return }
        let clip = scrollView.contentView.bounds
        let oldHeight = headerView.frame.height
        let atTop = abs(clip.minY + oldHeight) < 2

        headerView.frame.size.height = height
        headerView.superview?.needsDisplay = true
        scrollView.tile()
        if atTop {
            scrollView.contentView.scroll(to: NSPoint(x: clip.minX, y: -height))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func rebuildColumns(_ tableView: NSTableView) {
        for column in tableView.tableColumns {
            tableView.removeTableColumn(column)
        }
        for info in visibleColumns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(info.displayName))
            column.title = title(for: info)
            column.width = preferredWidth(for: info)
            column.minWidth = 60
            column.maxWidth = 420
            tableView.addTableColumn(column)
        }
        // 换完列紧接着的这一帧是用户第一次看见数据，用它作为打开耗时的收尾点。
        if let grid = tableView as? GridTableView {
            grid.awaitingFirstPaint = true
        }
        tableView.reloadData()
    }

    private func title(for info: ColumnInfo) -> String {
        guard let index = sorts.firstIndex(where: { $0.column == info.name }) else {
            return info.displayName
        }
        let arrow = sorts[index].ascending ? "↑" : "↓"
        if sorts.count == 1 {
            return "\(info.displayName) \(arrow)"
        }
        return "\(info.displayName) \(arrow)\(index + 1)"
    }

    private var visibleColumns: [ColumnInfo] {
        Self.visibleColumns(from: columns)
    }

    /// 超过上限时只留前 200 列。取数据也按这份裁剪后的列表查，宽表才不会整表卡住。
    public static func visibleColumns(from columns: [ColumnInfo]) -> [ColumnInfo] {
        ColumnVisibility.shown(columns, enabled: nil)
    }

    private func preferredWidth(for info: ColumnInfo) -> CGFloat {
        switch info.kind {
        case .integer: return 100
        case .double: return 120
        case .boolean: return 90
        case .date: return 120
        case .timestamp: return 180
        case .text: return 160
        }
    }
}
