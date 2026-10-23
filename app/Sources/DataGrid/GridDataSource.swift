import AppKit
import DuckDBKit

public final class GridDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var columns: [ColumnInfo] = []
    var rowCount: Int = 0
    var blockSize: Int = QuerySessionDefaults.blockSize
    var provider: ((Int, Int) throws -> TableBlock)?
    var onError: ((Error) -> Void)?

    private let cache = BlockCache(capacity: 8)
    private let cellIdentifier = NSUserInterfaceItemIdentifier("data-cell")

    public func numberOfRows(in tableView: NSTableView) -> Int {
        rowCount
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn else { return nil }

        if tableColumn.identifier.rawValue == "row-number" {
            let cell = reusableCell(in: tableView)
            cell.textField?.stringValue = String(row + 1)
            cell.textField?.alignment = .right
            cell.textField?.textColor = .secondaryLabelColor
            cell.textField?.toolTip = nil
            return cell
        }

        guard let columnIndex = columns.firstIndex(where: { $0.displayName == tableColumn.identifier.rawValue }) else {
            return nil
        }
        let info = columns[columnIndex]
        let value = cellValue(row: row, columnIndex: columnIndex)

        let cell = reusableCell(in: tableView)
        cell.textField?.stringValue = value ?? "NULL"
        cell.textField?.alignment = info.kind.isNumeric ? .right : .left
        cell.textField?.textColor = value == nil ? .tertiaryLabelColor : .labelColor
        cell.textField?.toolTip = value
        return cell
    }

    private func reusableCell(in tableView: NSTableView) -> NSTableCellView {
        if let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView {
            return cell
        }
        let cell = NSTableCellView()
        cell.identifier = cellIdentifier
        let field = NSTextField(labelWithString: "")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.lineBreakMode = .byTruncatingTail
        field.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private func cellValue(row: Int, columnIndex: Int) -> String? {
        guard row >= 0, row < rowCount else { return nil }
        let blockIndex = row / blockSize
        let block = cache.value(for: blockIndex) ?? loadBlock(blockIndex)
        guard let block else { return nil }
        let local = row - blockIndex * blockSize
        guard local >= 0, local < block.rows.count else { return nil }
        let values = block.rows[local]
        guard columnIndex < values.count else { return nil }
        return values[columnIndex]
    }

    private func loadBlock(_ blockIndex: Int) -> TableBlock? {
        guard let provider else { return nil }
        do {
            let block = try provider(blockIndex * blockSize, blockSize)
            cache.insert(block, for: blockIndex)
            return block
        } catch {
            onError?(error)
            return nil
        }
    }
}
