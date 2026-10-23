import Foundation
import DuckDBKit

/// 块缓存的 LRU。块索引 = 行号 / 块大小。
public final class BlockCache {
    private let capacity: Int
    private var storage: [Int: TableBlock] = [:]
    private var order: [Int] = []

    public init(capacity: Int = 8) {
        self.capacity = max(1, capacity)
    }

    public func value(for index: Int) -> TableBlock? {
        guard let block = storage[index] else { return nil }
        touch(index)
        return block
    }

    public func insert(_ block: TableBlock, for index: Int) {
        storage[index] = block
        touch(index)
        while order.count > capacity {
            let evicted = order.removeFirst()
            storage.removeValue(forKey: evicted)
        }
    }

    public func removeAll() {
        storage.removeAll()
        order.removeAll()
    }

    public var cachedCount: Int { storage.count }

    private func touch(_ index: Int) {
        if let position = order.firstIndex(of: index) {
            order.remove(at: position)
        }
        order.append(index)
    }
}
