import AppKit

public final class GridTableView: NSTableView {
    @objc public func copy(_ sender: Any?) {
        guard let source = dataSource as? GridDataSource else { return }
        let rows = selectedRowIndexes
        guard !rows.isEmpty else { return }

        let includeHeader = UserDefaults.standard.object(forKey: "copyIncludesHeader") as? Bool ?? true
        let text = source.tsv(for: rows, includeHeader: includeHeader)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
