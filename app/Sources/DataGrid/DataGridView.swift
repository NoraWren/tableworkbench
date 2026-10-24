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
    public let provider: (Int, Int) throws -> TableBlock
    public let onSortClick: (String, Bool) -> Void
    public let onError: (Error) -> Void

    public init(
        columns: [ColumnInfo],
        rowCount: Int,
        sorts: [SortSpec] = [],
        provider: @escaping (Int, Int) throws -> TableBlock,
        onSortClick: @escaping (String, Bool) -> Void = { _, _ in },
        onError: @escaping (Error) -> Void
    ) {
        self.columns = columns
        self.rowCount = rowCount
        self.sorts = sorts
        self.provider = provider
        self.onSortClick = onSortClick
        self.onError = onError
    }

    public func makeCoordinator() -> GridDataSource {
        let dataSource = GridDataSource()
        dataSource.columns = visibleColumns
        dataSource.rowCount = rowCount
        dataSource.provider = provider
        dataSource.onError = onError
        dataSource.onSortClick = onSortClick
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
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(rowNumbers)
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            rowNumbers.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            rowNumbers.topAnchor.constraint(equalTo: container.topAnchor),
            rowNumbers.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rowNumbers.widthAnchor.constraint(equalToConstant: Self.rowHeaderWidth),
            scrollView.leadingAnchor.constraint(equalTo: rowNumbers.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        rowNumbers.attach(tableView: tableView, scrollView: scrollView)
        context.coordinator.contentTableView = tableView
        context.coordinator.rowNumbersView = rowNumbers
        rebuildColumns(tableView)
        return container
    }

    public func updateNSView(_ view: NSView, context: Context) {
        let dataSource = context.coordinator
        dataSource.provider = provider
        dataSource.onError = onError
        dataSource.onSortClick = onSortClick
        dataSource.computedColumnNames = Set(columns.filter(\.isComputed).map(\.name))

        let changed = dataSource.columns != visibleColumns
            || dataSource.rowCount != rowCount
            || dataSource.sorts != sorts
        dataSource.columns = visibleColumns
        dataSource.rowCount = rowCount
        dataSource.sorts = sorts

        if changed, let tableView = dataSource.contentTableView {
            dataSource.resetFailedBlocks()
            rebuildColumns(tableView)
        }
        dataSource.rowNumbersView?.needsDisplay = true
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
