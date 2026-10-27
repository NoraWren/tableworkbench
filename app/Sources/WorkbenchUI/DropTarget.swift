import SwiftUI
import AppKit

/// 访达拖文件进窗口，由这一层接。
///
/// 为什么不用 SwiftUI 的 dropDestination：它挂在 NavigationSplitView 的兄弟层上，
/// 生成的 _PlatformDraggingDestinationView 和分栏视图并列。AppKit 投递拖放的规则是
/// 先 hitTest 找到最深的视图，再沿父链往上找注册了拖放类型的那个；兄弟链不在父链上，
/// 于是拖拽落不到它身上（离屏探针在 TableWorkbenchUIAudit 里可复现）。
///
/// 这里把整窗内容套进一个注册了 public.file-url 的容器视图，任何位置的父链都能走回它。
/// 顺带解决了 NSTableView 会不会抢走拖拽的问题：容器是表格的祖先，抢不走。

/// 闭包要能就地换掉，容器持有盒子，SwiftUI 每次更新只改盒子里的函数。
public final class DropHandlerBox {
    public var handle: ([URL]) -> Void
    public init(_ handle: @escaping ([URL]) -> Void) {
        self.handle = handle
    }
}

public final class FileDropContainerView: NSView {
    public let box: DropHandlerBox

    public init(frame frameRect: NSRect, box: DropHandlerBox) {
        self.box = box
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("不支持从 nib 加载") }

    /// 从拖拽剪贴板里只取本地文件 URL，其他内容一律不要。
    public static func fileURLs(in pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let items = pasteboard.readObjects(forClasses: [NSURL.self], options: options) else {
            return []
        }
        return items.compactMap { ($0 as? NSURL) as URL? }
    }

    private func urls(from info: NSDraggingInfo) -> [URL] {
        Self.fileURLs(in: info.draggingPasteboard)
    }

    private func setHighlighted(_ on: Bool) {
        guard let layer else { return }
        layer.borderWidth = on ? 3 : 0
        layer.borderColor = NSColor.controlAccentColor.cgColor
        layer.cornerRadius = on ? 10 : 0
    }

    public override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation {
        guard !urls(from: info).isEmpty else { return [] }
        setHighlighted(true)
        return .copy
    }

    public override func draggingUpdated(_ info: NSDraggingInfo) -> NSDragOperation {
        urls(from: info).isEmpty ? [] : .copy
    }

    public override func draggingExited(_ info: NSDraggingInfo?) {
        setHighlighted(false)
    }

    public override func prepareForDragOperation(_ info: NSDraggingInfo) -> Bool {
        !urls(from: info).isEmpty
    }

    public override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        setHighlighted(false)
        let dropped = urls(from: info)
        guard !dropped.isEmpty else { return false }
        box.handle(dropped)
        return true
    }

    public override func concludeDragOperation(_ info: NSDraggingInfo?) {
        setHighlighted(false)
    }
}

@MainActor
public enum WindowDropInstaller {
    /// 把窗口内容视图换成拖放容器，原来的内容视图塞进去铺满。
    /// 重复调用只换处理函数，不会套第二层。
    ///
    /// 必须等 SwiftUI 把 hosting 视图安顿好再换。在 viewDidMoveToWindow 里当场换，
    /// SwiftUI 随后会把 hosting 视图重新挂回 NSThemeFrame，容器就空了。
    @discardableResult
    public static func install(on window: NSWindow, handler: @escaping ([URL]) -> Void) -> FileDropContainerView? {
        if let container = window.contentView as? FileDropContainerView {
            container.box.handle = handler
            return container
        }
        guard let content = window.contentView, content.superview != nil else { return nil }
        let container = FileDropContainerView(frame: content.frame, box: DropHandlerBox(handler))
        container.autoresizingMask = [.width, .height]
        window.contentView = container
        content.autoresizingMask = [.width, .height]
        content.frame = container.bounds
        container.addSubview(content)
        // 换完之后再确认一次：SwiftUI 有时会在同一轮里又把 hosting 挪走。
        if content.superview !== container {
            container.addSubview(content)
            content.frame = container.bounds
        }
        return container
    }
}

/// 挂在 SwiftUI 树里只为拿到窗口，真正的接收器是窗口内容视图那一层。
struct DropTargetInstaller: NSViewRepresentable {
    let handler: ([URL]) -> Void

    func makeNSView(context: Context) -> NSView {
        let probe = WindowProbeView()
        probe.box.handle = handler
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowProbeView)?.box.handle = handler
    }

    final class WindowProbeView: NSView {
        let box = DropHandlerBox { _ in }
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            install(on: window)
            // 进出全屏、从程序坞里恢复时 AppKit 会重建窗口的内容视图，容器跟着没了，
            // 得再装一次。多挂两个通知的代价只是改一个闭包引用，不用重新建视图。
            for name in [
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification,
                NSWindow.didDeminiaturizeNotification,
                NSWindow.didBecomeMainNotification
            ] {
                let observer = NotificationCenter.default.addObserver(
                    forName: name,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    MainActor.assumeIsolated {
                        guard let self, let window else { return }
                        self.install(on: window)
                    }
                }
                observers.append(observer)
            }
        }

        /// 挪到下一轮再装，等 SwiftUI 把 hosting 视图挂稳。
        private func install(on window: NSWindow) {
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                WindowDropInstaller.install(on: window, handler: { urls in self.box.handle(urls) })
            }
        }
    }
}
