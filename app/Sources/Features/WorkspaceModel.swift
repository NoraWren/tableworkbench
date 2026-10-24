import Foundation
import Combine
import DuckDBKit

@MainActor
public final class WorkspaceModel: ObservableObject {
    public struct Entry: Identifiable {
        public let id: UUID
        public let url: URL
        public let session: QuerySession
        public let encoding: TextEncoding
        public var sort: [SortSpec] = []
        public var filter: FilterGroup?
        public var resultCount: Int
        public var queryVersion: Int = 0

        public init(id: UUID = UUID(), url: URL, session: QuerySession, encoding: TextEncoding) {
            self.id = id
            self.url = url
            self.session = session
            self.encoding = encoding
            self.resultCount = session.rowCount
        }

        public var displayName: String { url.lastPathComponent }
        public var rowCount: Int { session.rowCount }
        public var columns: [ColumnInfo] { session.columns }
    }

    @Published public private(set) var entries: [Entry] = []
    @Published public var selection: UUID?
    @Published public private(set) var error: ImportError?
    @Published public private(set) var isLoading = false
    @Published public private(set) var isQuerying = false
    @Published public private(set) var sqlResult: SQLResult?
    @Published public private(set) var isRunningSQL = false

    public init() {}

    public var selectedEntry: Entry? {
        guard let selection else { return nil }
        return entries.first { $0.id == selection }
    }

    public func open(urls: [URL]) {
        guard !urls.isEmpty else { return }
        isLoading = true
        error = nil

        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (files: [OpenedFile], error: ImportError?) in
                var files: [OpenedFile] = []
                var firstError: ImportError?
                for url in urls {
                    do {
                        files.append(try FileImporter.open(url: url))
                    } catch let importError as ImportError {
                        if firstError == nil { firstError = importError }
                    } catch {
                        if firstError == nil { firstError = ImportError.wrap(error, step: "打开文件") }
                    }
                }
                return (files, firstError)
            }.value

            for file in result.files {
                let entry = Entry(url: file.url, session: file.session, encoding: file.encoding)
                entries.append(entry)
                if selection == nil { selection = entry.id }
            }
            error = result.error
            isLoading = false
        }
    }

    public func toggleSort(entryID: UUID, column: String, additive: Bool) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        var sorts = entries[index].sort

        if additive {
            if let position = sorts.firstIndex(where: { $0.column == column }) {
                if sorts[position].ascending {
                    sorts[position] = SortSpec(column: column, ascending: false)
                } else {
                    sorts.remove(at: position)
                }
            } else {
                sorts.append(SortSpec(column: column, ascending: true))
            }
        } else {
            if sorts.count == 1, sorts[0].column == column {
                sorts = sorts[0].ascending
                    ? [SortSpec(column: column, ascending: false)]
                    : []
            } else {
                sorts = [SortSpec(column: column, ascending: true)]
            }
        }

        apply(view: QueryView(sort: sorts, filter: entries[index].filter), to: index)
    }

    public func applyFilter(entryID: UUID, filter: FilterGroup?) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        apply(view: QueryView(sort: entries[index].sort, filter: filter), to: index)
    }

    private func apply(view: QueryView, to index: Int) {
        let session = entries[index].session
        isQuerying = true

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (count: Int?, error: ImportError?) in
                do {
                    try session.apply(view: view)
                    return (session.resultCount, nil)
                } catch let importError as ImportError {
                    return (nil, importError)
                } catch {
                    return (nil, ImportError.wrap(error, step: "执行查询"))
                }
            }.value

            if let count = outcome.count {
                entries[index].sort = view.sort
                entries[index].filter = view.filter
                entries[index].resultCount = count
                entries[index].queryVersion += 1
            } else {
                error = outcome.error
            }
            isQuerying = false
        }
    }

    public func runSQL(entryID: UUID, sql: String) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let session = entries[index].session
        isRunningSQL = true
        sqlResult = nil

        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (SQLResult?, ImportError?) in
                do {
                    return (try session.runSQL(trimmed), nil)
                } catch let importError as ImportError {
                    return (nil, importError)
                } catch {
                    return (nil, ImportError.wrap(error, step: "执行 SQL"))
                }
            }.value

            if let result = outcome.0 {
                sqlResult = result
            } else {
                error = outcome.1
            }
            isRunningSQL = false
        }
    }

    public func clearSQLResult() {
        sqlResult = nil
    }

    public func closeSelected() {
        guard let selection, let index = entries.firstIndex(where: { $0.id == selection }) else { return }
        entries[index].session.close()
        entries.remove(at: index)
        self.selection = entries.first?.id
    }

    public func report(_ error: ImportError) {
        self.error = error
    }

    public func dismissError() {
        error = nil
    }
}
