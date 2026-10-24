import Foundation
import CryptoKit
import DuckDB

public final class ParquetCache: @unchecked Sendable {
    public static var shared = ParquetCache()

    public let baseDirectory: URL
    public let limitBytes: Int64
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

    public func scheduleConversion(sourceKey: URL, readableURL: URL, format: CSVFormat, variant: String) {
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
            defer { self.finish(cacheKey) }
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
        try? FileManager.default.setAttributes([.modificationDate: Foundation.Date()], ofItemAtPath: finalURL.path)
        evictIfNeeded(keeping: finalURL)
    }

    public func evictIfNeeded(keeping current: URL?) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let entries: [(url: URL, size: Int64, date: Foundation.Date)] = files.compactMap { url in
            guard url.pathExtension == "parquet" else { return nil }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return (url, Int64(values?.fileSize ?? 0), values?.contentModificationDate ?? .distantPast)
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
