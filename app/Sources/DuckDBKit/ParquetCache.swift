import Foundation
import CryptoKit
import DuckDB

public final class ParquetCache: @unchecked Sendable {
    public static var shared = ParquetCache()

    public let baseDirectory: URL
    public private(set) var limitBytes: Int64
    private let version = "v1"
    private let lock = NSLock()
    private var inFlight: Set<String> = []

    public init(baseDirectory: URL? = nil, limitBytes: Int64 = 10 * 1024 * 1024 * 1024) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            self.baseDirectory = support.appendingPathComponent("TableWorkbench/cache", isDirectory: true)
        }
        self.limitBytes = limitBytes
        try? FileManager.default.createDirectory(at: self.baseDirectory, withIntermediateDirectories: true)
        // 上次进程被强杀留下的临时文件不会被任何转换认领，开机时清一次。
        sweepStaleTemporaries()
    }

    public func cachedURL(for source: URL, variant: String) -> URL? {
        let url = cacheURL(for: source, variant: variant)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Foundation.Date()], ofItemAtPath: url.path)
        return url
    }

    public func cacheURL(for source: URL, variant: String) -> URL {
        baseDirectory.appendingPathComponent("\(key(for: source, variant: variant)).parquet")
    }

    public func scheduleConversion(
        sourceKey: URL,
        readableURL: URL,
        format: CSVFormat,
        variant: String,
        cleanupAfterConversion: Bool = false
    ) {
        let cacheKey = key(for: sourceKey, variant: variant)
        lock.lock()
        if inFlight.contains(cacheKey) {
            lock.unlock()
            return
        }
        inFlight.insert(cacheKey)
        lock.unlock()

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                self.finish(cacheKey)
                if cleanupAfterConversion {
                    try? FileManager.default.removeItem(at: readableURL)
                }
            }
            try? self.convert(readableURL: readableURL, format: format, key: cacheKey)
        }
    }

    private func finish(_ key: String) {
        lock.lock()
        inFlight.remove(key)
        lock.unlock()
    }

    private func key(for source: URL, variant: String) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: source.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes?[.modificationDate] as? Foundation.Date)?.timeIntervalSince1970 ?? 0
        let raw = "\(source.path)|\(size)|\(Int64(modified))|\(version)|\(variant)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func convert(readableURL: URL, format: CSVFormat, key: String) throws {
        let finalURL = baseDirectory.appendingPathComponent("\(key).parquet")
        if FileManager.default.fileExists(atPath: finalURL.path) { return }

        let temporaryURL = baseDirectory.appendingPathComponent("\(key).parquet.tmp")
        try? FileManager.default.removeItem(at: temporaryURL)
        // 转换中途抛错时自己收拾，不等下一次转换顺手删：用户可能再也不打开这个文件。
        var succeeded = false
        defer {
            if !succeeded { try? FileManager.default.removeItem(at: temporaryURL) }
        }

        let database = try Database(store: .inMemory)
        let connection = try database.connect()
        try connection.execute("SET memory_limit='384MB'")
        try connection.execute("SET threads=4")

        let path = readableURL.path.replacingOccurrences(of: "'", with: "''")
        let destination = temporaryURL.path.replacingOccurrences(of: "'", with: "''")
        let delimiter = format.delimiter == "\t" ? "\t" : String(format.delimiter)
        let delimiterLiteral = delimiter.replacingOccurrences(of: "'", with: "''")
        let header = format.hasHeader ? "true" : "false"

        let sql = """
        COPY (
            SELECT * FROM read_csv_auto('\(path)', delim='\(delimiterLiteral)', header=\(header), auto_detect=true)
        ) TO '\(destination)' (FORMAT PARQUET, COMPRESSION SNAPPY)
        """
        try connection.execute(sql)
        try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
        succeeded = true
        try? FileManager.default.setAttributes([.modificationDate: Foundation.Date()], ofItemAtPath: finalURL.path)
        evictIfNeeded(keeping: finalURL)
    }

    public func setLimitBytes(_ value: Int64) {
        lock.lock()
        limitBytes = max(0, value)
        lock.unlock()
        evictIfNeeded(keeping: nil)
    }

    public func clearAll() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files where isCacheFile(file) {
            try? fileManager.removeItem(at: file)
        }
    }

    public func totalSizeBytes() -> Int64 {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        return files.reduce(Int64(0)) { total, file in
            // 半截的 .parquet.tmp 也占着磁盘，漏算它们，10 GB 上限就是假的。
            guard isCacheFile(file) else { return total }
            let values = try? file.resourceValues(forKeys: [.fileSizeKey])
            return total + Int64(values?.fileSize ?? 0)
        }
    }

    /// 缓存目录里算作占用的文件：正式产物与转换中的临时文件。
    private func isCacheFile(_ url: URL) -> Bool {
        url.pathExtension == "parquet" || url.lastPathComponent.hasSuffix(".parquet.tmp")
    }

    /// 清扫上次进程被强杀留下的临时文件。阈值取 1 小时：正常转换只要几秒，
    /// 留出三个数量级的余量，不会误删别的进程正在写的文件。
    public func sweepStaleTemporaries(olderThan seconds: TimeInterval = 3600) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Foundation.Date().addingTimeInterval(-seconds)
        for file in files where file.lastPathComponent.hasSuffix(".parquet.tmp") {
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modified = values?.contentModificationDate, modified < cutoff else { continue }
            try? fileManager.removeItem(at: file)
        }
    }

    public func evictIfNeeded(keeping current: URL?) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let entries: [(url: URL, size: Int64, date: Foundation.Date)] = files.compactMap { url in
            guard isCacheFile(url) else { return nil }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let modified = values?.contentModificationDate ?? .distantPast
            // 正在写的临时文件不能被淘汰，否则会把手上的转换打断。只认过期的那些。
            if url.lastPathComponent.hasSuffix(".parquet.tmp"),
               modified > Foundation.Date().addingTimeInterval(-3600) {
                return nil
            }
            return (url, Int64(values?.fileSize ?? 0), modified)
        }

        var total = entries.reduce(Int64(0)) { $0 + $1.size }
        guard total > limitBytes else { return }

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            if total <= limitBytes { break }
            if let current,
               entry.url.standardizedFileURL.path == current.standardizedFileURL.path {
                continue
            }
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}
