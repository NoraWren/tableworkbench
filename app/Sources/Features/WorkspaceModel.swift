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

        public init(id: UUID = UUID(), url: URL, session: QuerySession, encoding: TextEncoding) {
            self.id = id
            self.url = url
            self.session = session
            self.encoding = encoding
        }

        public var displayName: String { url.lastPathComponent }
        public var rowCount: Int { session.rowCount }
        public var columns: [ColumnInfo] { session.columns }
    }

    @Published public private(set) var entries: [Entry] = []
    @Published public var selection: UUID?
    @Published public private(set) var error: ImportError?
    @Published public private(set) var isLoading = false

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
