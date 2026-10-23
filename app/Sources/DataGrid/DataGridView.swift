import SwiftUI
import AppKit
import DuckDBKit

public struct DataGridView: NSViewRepresentable {
    public static let maxVisibleColumns = 2000
    public static let defaultVisibleColumns = 200

    public let columns: [ColumnInfo]
    public let rowCount: Int
    public let provider: (Int, Int) throws -> TableBlock
    public let onError: (Error) -> Void

    public init(
        columns: [ColumnInfo],
        rowCount: Int,
        provider: @escaping (Int, Int) throws -> TableBlock,
        onError: @escaping (Error) -> Void
    ) {
        self.columns = columns
        self.rowCount = rowCount
        self.provider = provider
        self.onError = onError
    }

    public func makeCoordinator() -> GridDataSource {
        let dataSource = GridDataSource()
        dataSource.columns = visibleColumns
        dataSource.rowCount = rowCount
        dataSource.provider = provider
        dataSource.onError = onError
        return dataSource
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowSizeStyle = .medium
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = false
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        rebuildColumns(tableView)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        let dataSource = context.coordinator
        dataSource.provider = provider
        dataSource.onError = onError

        let changed = dataSource.columns != visibleColumns || dataSource.rowCount != rowCount
        dataSource.columns = visibleColumns
        dataSource.rowCount = rowCount
        if changed {
            rebuildColumns(tableView)
        }
    }

    private func rebuildColumns(_ tableView: NSTableView) {
        for column in tableView.tableColumns {
            tableView.removeTableColumn(column)
        }

        let rowNumber = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row-number"))
        rowNumber.title = "#"
        rowNumber.width = 56
        rowNumber.minWidth = 44
        rowNumber.maxWidth = 80
        tableView.addTableColumn(rowNumber)

        for info in visibleColumns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(info.displayName))
            column.title = info.displayName
            column.width = preferredWidth(for: info)
            column.minWidth = 60
            column.maxWidth = 420
            tableView.addTableColumn(column)
        }
        tableView.reloadData()
    }

    private var visibleColumns: [ColumnInfo] {
        if columns.count > Self.maxVisibleColumns {
            return Array(columns.prefix(Self.defaultVisibleColumns))
        }
        return columns
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
