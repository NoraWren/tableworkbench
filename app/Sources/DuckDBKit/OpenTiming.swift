import Foundation

/// 打开耗时的分段打点，只在设了 `TW_OPEN_TIMING` 时生效。
///
/// 为什么要有它：R-IMP-01 的验收是"从松手到表格可滚动不超过 2 秒"，而 `bench.sh`
/// 跑的是无界面路径（打开到取到第一块）。两者差在"取到第一块"到"画出来"这一段，
/// 靠录屏逐帧算只能拿到粗粒度结果，还容易被自动化拖拽的偶发失败带偏。
/// 这里把打点放进应用自己，每个点都带相对起点的秒数，外部脚本不用参与计时。
///
/// 起点的规则：默认是进程启动；拖放落到窗口上时由 `restart()` 挪到松手那一刻。
/// 输出走标准错误；`open -a` 拉起的实例拿不到标准错误，所以再支持
/// `TW_OPEN_TIMING_FILE`，设了就同时追加到那个文件。
public enum OpenTiming {
    private static let lock = NSLock()
    private static var start = Date()

    public static let isEnabled = ProcessInfo.processInfo.environment["TW_OPEN_TIMING"] != nil

    private static let sinkURL: URL? = ProcessInfo.processInfo
        .environment["TW_OPEN_TIMING_FILE"]
        .map { URL(fileURLWithPath: $0) }

    /// 拖放松手时调用，把计时起点挪到这一刻。
    public static func restart() {
        guard isEnabled else { return }
        lock.lock()
        start = Date()
        lock.unlock()
    }

    /// 记一个点，标签用中文，写进日志时带上相对起点的秒数。
    public static func mark(_ label: String) {
        guard isEnabled else { return }
        lock.lock()
        let elapsed = Date().timeIntervalSince(start)
        lock.unlock()
        let line = String(format: "[open] %@ +%.3f 秒\n", label, elapsed)
        FileHandle.standardError.write(Data(line.utf8))
        guard let sinkURL else { return }
        if let handle = try? FileHandle(forWritingTo: sinkURL) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: sinkURL)
        }
    }
}
