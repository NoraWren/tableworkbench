import SwiftUI
import AppKit
import DuckDBKit
import Features

/// SQL 编辑器。AppKit 的 NSTextView 才能拿到光标位置、拦 Tab 和回车，SwiftUI 的 TextEditor 两者都做不到。
/// 补全候选来自当前会话的表与列，逻辑在 SQLCompletion，这里只管弹窗和按键。
public struct SQLTextView: NSViewRepresentable {
    @Binding var text: String
    let columns: [String]
    let tables: [String]

    public init(text: Binding<String>, columns: [String], tables: [String]) {
        self._text = text
        self.columns = columns
        self.tables = tables
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let textView = CompletionTextView()
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.string = text
        textView.delegate = context.coordinator
        textView.completionSource = context.coordinator
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        context.coordinator.textView = textView

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.columns = columns
        context.coordinator.tables = tables
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text, !context.coordinator.isEditing {
            textView.string = text
        }
    }

    public final class Coordinator: NSObject, NSTextViewDelegate, SQLCompletionSource {
        private let text: Binding<String>
        public weak var textView: NSTextView?
        public var columns: [String] = []
        public var tables: [String] = []
        var isEditing = false

        public init(text: Binding<String>) {
            self.text = text
        }

        public func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
        }

        public func textDidEndEditing(_ notification: Notification) {
            isEditing = false
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            if let typed = textView as? CompletionTextView {
                typed.refreshCompletion()
            }
        }

        // MARK: - SQLCompletionSource

        public func completionCandidates(for textView: NSTextView) -> [String] {
            let caret = textView.selectedRange().location
            guard let context = SQLCompletion.context(
                in: textView.string,
                caret: caret,
                tables: tables
            ) else { return [] }
            return SQLCompletion.candidates(context: context, columns: columns, tables: tables)
        }

        public func applyCompletion(_ candidate: String, in textView: NSTextView) {
            let caret = textView.selectedRange().location
            guard let applied = SQLCompletion.apply(candidate: candidate, to: textView.string, caret: caret) else {
                return
            }
            textView.string = applied.text
            textView.setSelectedRange(NSRange(location: applied.caret, length: 0))
            text.wrappedValue = applied.text
            textView.didChangeText()
        }
    }
}

public protocol SQLCompletionSource: AnyObject {
    func completionCandidates(for textView: NSTextView) -> [String]
    func applyCompletion(_ candidate: String, in textView: NSTextView)
}

/// 带补全弹窗的 NSTextView。
///
/// Tab、回车、上下键在弹窗可见时归弹窗用；弹窗不可见时一律交回系统，
/// 所以普通输入、Command+R 运行、拖选都不受影响。
public final class CompletionTextView: NSTextView {
    public weak var completionSource: SQLCompletionSource?

    private var popup: CompletionPopup?
    private var candidates: [String] = []

    /// 弹窗当前是否可见，测试与界面状态用。
    public var isSuggesting: Bool { popup != nil }
    /// 当前候选，按弹窗顺序。
    public var suggestions: [String] { candidates }
    /// 当前选中的候选序号。
    public var selectedSuggestion: Int { popup?.selectedIndex ?? 0 }
    /// 弹窗在屏幕上的位置，测试定位用。不可见时为 nil。
    public var suggestingFrame: NSRect? { popup?.frame }

    public override func keyDown(with event: NSEvent) {
        if popup != nil {
            switch event.keyCode {
            case 53: // Esc
                closePopup()
                return
            case 125: // 下
                popup?.moveSelection(by: 1)
                return
            case 126: // 上
                popup?.moveSelection(by: -1)
                return
            case 36, 48, 76: // 回车、Tab、小键盘回车
                acceptSelected()
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    public override func didChangeText() {
        super.didChangeText()
        refreshCompletion()
    }

    public override func resignFirstResponder() -> Bool {
        closePopup()
        return super.resignFirstResponder()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { closePopup() }
    }

    /// 按当前光标重新算候选。前缀为空、光标在字符串或注释里时不弹。
    public func refreshCompletion() {
        guard let source = completionSource else { return closePopup() }
        let found = source.completionCandidates(for: self)
        guard !found.isEmpty else { return closePopup() }
        candidates = found
        let popup = ensurePopup()
        popup.update(items: found)
        position(popup)
    }

    private func ensurePopup() -> CompletionPopup {
        if let popup { return popup }
        let created = CompletionPopup()
        created.onPick = { [weak self] index in
            guard let self, index < self.candidates.count else { return }
            self.pick(self.candidates[index])
        }
        popup = created
        return created
    }

    /// 贴在光标下方；下方放不下就翻到上方，并夹在可见范围内。
    private func position(_ popup: CompletionPopup) {
        guard let window, let caretRect = caretScreenRect() else { return }

        let size = popup.frame.size
        var origin = NSPoint(x: caretRect.minX, y: caretRect.minY - size.height - 2)
        // 下方放不下就翻到上方；再夹进屏幕，免得半截露在窗口外。
        if origin.y < (window.screen?.visibleFrame.minY ?? 0) {
            origin.y = caretRect.maxY + 2
        }
        if let visible = window.screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        popup.setFrameOrigin(origin)
        popup.orderFront(nil)
    }

    /// 光标在屏幕坐标里的矩形。
    ///
    /// 不用布局引擎的 boundingRect 算：光标停在文本末尾时那个范围是零长度，
    /// 取出来是空矩形，弹窗会跑到编辑器左下角。firstRect 走的是输入法那一套，
    /// 对空选区也给出所在行的矩形。
    private func caretScreenRect() -> NSRect? {
        var actual = NSRange()
        let rect = firstRect(
            forCharacterRange: NSRange(location: selectedRange().location, length: 0),
            actualRange: &actual
        )
        guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.height > 0 else { return nil }
        return rect
    }

    private func acceptSelected() {
        guard let index = popup?.selectedIndex, index < candidates.count else {
            closePopup()
            return
        }
        acceptSuggestion(at: index)
    }

    private func pick(_ candidate: String) {
        closePopup()
        completionSource?.applyCompletion(candidate, in: self)
        // 接受后再算一次，允许连续补全（data.金 → data.金额）。
        refreshCompletion()
    }

    public func closePopup() {
        popup?.orderOut(nil)
        popup = nil
        candidates = []
    }

    /// 接受第 index 个候选。按键路径与测试都走这里。
    public func acceptSuggestion(at index: Int) {
        guard index >= 0, index < candidates.count else {
            closePopup()
            return
        }
        pick(candidates[index])
    }

    deinit {
        // deinit 里不碰窗口，只把面板摘掉。
        popup?.orderOut(nil)
    }
}

/// 无边框候选面板：一张单列表格，点击或按回车接受。
final class CompletionPopup: NSPanel {
    var onPick: ((Int) -> Void)?
    private let table = NSTableView()
    private var items: [String] = []
    private(set) var selectedIndex = 0

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 160),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .transient]

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("candidate"))
        column.width = 240
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 20
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        table.backgroundColor = .controlBackgroundColor
        table.style = .plain

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .controlBackgroundColor

        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.layer?.masksToBounds = true
        scroll.frame = container.bounds
        scroll.autoresizingMask = [.width, .height]
        container.addSubview(scroll)
        contentView = container
    }

    func update(items: [String]) {
        self.items = items
        selectedIndex = 0
        table.reloadData()
        if !items.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            table.scrollRowToVisible(0)
        }
        let height = CGFloat(min(items.count, 8)) * table.rowHeight + 8
        setContentSize(NSSize(width: 260, height: max(28, height)))
        table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("candidate"))?.width = 240
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + items.count) % items.count
        table.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        table.scrollRowToVisible(selectedIndex)
    }

    @objc private func rowClicked() {
        onPick?(table.clickedRow)
    }
}

extension CompletionPopup: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let label: NSTextField
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField {
            label = reused
        } else {
            label = NSTextField(labelWithString: "")
            label.identifier = identifier
            label.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            label.lineBreakMode = .byTruncatingTail
        }
        label.stringValue = row < items.count ? items[row] : ""
        return label
    }
}

