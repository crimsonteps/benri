import Combine
import Darwin
import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
public final class ClipboardStore: ObservableObject {
    @Published public private(set) var items: [ClipboardItem] = []

    public let directoryURL: URL
    public let databaseURL: URL
    public let imagesDirectoryURL: URL
    public var maxAge: TimeInterval = ClipboardRetention.threeMonths.maxAge

    private static let memoryWindow = 1_000
    private var database: OpaquePointer?
    private var supportsTrigramSearch = false

    public init(directoryURL: URL? = nil) {
        let resolvedDirectory = directoryURL ?? Self.defaultDirectoryURL()
        self.directoryURL = resolvedDirectory
        databaseURL = resolvedDirectory.appendingPathComponent("clipboard.sqlite3")
        imagesDirectoryURL = resolvedDirectory.appendingPathComponent("images", isDirectory: true)
        openDatabase()
        load()
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    public static func defaultDirectoryURL(
        fileManager: FileManager = .default
    ) -> URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.crimsonteps.benri", isDirectory: true)
            .appendingPathComponent("Clipboard", isDirectory: true)
    }

    public func load() {
        guard database != nil else { return }
        enforceLimits(reload: false)
        let sql = """
        SELECT id, kind, text, image_path, created_at, source_bundle_id, pinned_at
        FROM items
        WHERE pinned_at IS NOT NULL OR created_at >= ?
        ORDER BY created_at DESC
        """
        let cutoff = Date().addingTimeInterval(-maxAge).timeIntervalSince1970
        items = query(sql: sql, bind: { statement in
            sqlite3_bind_double(statement, 1, cutoff)
        })
        trimMemoryWindow()
    }

    public func search(_ query: String) -> [ClipboardItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ordered(items)
        } else if supportsTrigramSearch, trimmed.count >= 3 {
            return searchDatabase(trimmed)
        } else {
            return searchDatabaseWithoutFTS(trimmed)
        }
    }

    public func addText(_ text: String, sourceBundleID: String?) {
        if items.first?.kind == .text, items.first?.text == text { return }
        insert(
            ClipboardItem(kind: .text, text: text, sourceBundleID: sourceBundleID)
        )
    }

    @discardableResult
    public func addImage(
        _ data: Data,
        sourceBundleID: String?,
        createdAt: Date = Date()
    ) throws -> ClipboardItem {
        let fileURL = imagesDirectoryURL
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
        let item = ClipboardItem(
            kind: .image,
            imagePath: fileURL.path,
            createdAt: createdAt,
            sourceBundleID: sourceBundleID
        )
        insert(item)
        return item
    }

    public func imageURL(for item: ClipboardItem) -> URL? {
        item.imagePath.map(URL.init(fileURLWithPath:))
    }

    public func remove(_ item: ClipboardItem) {
        execute("DELETE FROM items WHERE id = ?", textValues: [item.id.uuidString])
        execute("DELETE FROM items_fts WHERE id = ?", textValues: [item.id.uuidString])
        deleteOwnedImage(for: item)
        items.removeAll { $0.id == item.id }
    }

    public func clearAll() {
        execute("DELETE FROM items")
        execute("DELETE FROM items_fts")
        let fileManager = FileManager.default
        if let files = try? fileManager.contentsOfDirectory(
            at: imagesDirectoryURL,
            includingPropertiesForKeys: nil
        ) {
            for file in files { try? fileManager.removeItem(at: file) }
        }
        items = []
    }

    public func togglePinned(_ item: ClipboardItem) {
        if item.isPinned {
            let updated = item.replacing(createdAt: Date(), pinnedAt: nil)
            update(updated)
        } else {
            update(item.replacing(pinnedAt: Date()))
        }
    }

    public func promote(_ item: ClipboardItem) {
        guard !item.isPinned else { return }
        update(item.replacing(createdAt: Date(), pinnedAt: nil))
    }

    public func enforceLimits(reload: Bool = true) {
        guard maxAge < .greatestFiniteMagnitude else {
            if reload { load() }
            return
        }
        let cutoff = Date().addingTimeInterval(-maxAge).timeIntervalSince1970
        let stale = query(
            sql: """
            SELECT id, kind, text, image_path, created_at, source_bundle_id, pinned_at
            FROM items WHERE pinned_at IS NULL AND created_at < ?
            """,
            bind: { sqlite3_bind_double($0, 1, cutoff) }
        )
        execute("DELETE FROM items WHERE pinned_at IS NULL AND created_at < ?", doubleValue: cutoff)
        for item in stale {
            execute("DELETE FROM items_fts WHERE id = ?", textValues: [item.id.uuidString])
            deleteOwnedImage(for: item)
        }
        if reload { load() }
    }

    private func openDatabase() {
        do {
            try FileManager.default.createDirectory(
                at: imagesDirectoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directoryURL.path
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: imagesDirectoryURL.path
            )
        } catch {
            return
        }

        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            database = nil
            return
        }
        sqlite3_busy_timeout(database, 1_000)
        execute("PRAGMA journal_mode=WAL")
        execute("PRAGMA synchronous=NORMAL")
        let createdSchema = executeRaw("""
        CREATE TABLE IF NOT EXISTS items (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            text TEXT,
            image_path TEXT,
            created_at REAL NOT NULL,
            source_bundle_id TEXT,
            pinned_at REAL
        )
        """)
        if !createdSchema {
            closeDatabase()
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
            }
            guard sqlite3_open_v2(
                databaseURL.path,
                &database,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                nil
            ) == SQLITE_OK else {
                database = nil
                return
            }
            sqlite3_busy_timeout(database, 1_000)
            guard executeRaw("""
            CREATE TABLE items (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                text TEXT,
                image_path TEXT,
                created_at REAL NOT NULL,
                source_bundle_id TEXT,
                pinned_at REAL
            )
            """) else {
                closeDatabase()
                return
            }
        }
        execute("CREATE INDEX IF NOT EXISTS items_created_at ON items(created_at DESC)")
        execute("CREATE INDEX IF NOT EXISTS items_pinned_at ON items(pinned_at)")
        supportsTrigramSearch = sqlite3_exec(
            database,
            "CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(id UNINDEXED, text, tokenize='trigram')",
            nil,
            nil,
            nil
        ) == SQLITE_OK
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: databaseURL.path
        )
    }

    private func insert(_ item: ClipboardItem) {
        let sql = """
        INSERT OR REPLACE INTO items
        (id, kind, text, image_path, created_at, source_bundle_id, pinned_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        guard let statement = prepare(sql) else {
            items.removeAll { $0.id == item.id }
            items.insert(item, at: 0)
            trimMemoryWindow()
            return
        }
        defer { sqlite3_finalize(statement) }
        bind(item, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { return }
        index(item)
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        trimMemoryWindow()
        enforceLimits(reload: false)
    }

    private func update(_ item: ClipboardItem) {
        insert(item)
        load()
    }

    private func index(_ item: ClipboardItem) {
        guard supportsTrigramSearch else { return }
        execute("DELETE FROM items_fts WHERE id = ?", textValues: [item.id.uuidString])
        guard item.kind == .text, let text = item.text else { return }
        execute("INSERT INTO items_fts(id, text) VALUES (?, ?)", textValues: [item.id.uuidString, text])
    }

    private func searchDatabase(_ value: String) -> [ClipboardItem] {
        let sql = """
        SELECT i.id, i.kind, i.text, i.image_path, i.created_at, i.source_bundle_id, i.pinned_at
        FROM items_fts f JOIN items i ON i.id = f.id
        WHERE f.text MATCH ?
        ORDER BY (i.pinned_at IS NULL), i.pinned_at ASC, i.created_at DESC
        LIMIT 500
        """
        let escaped = "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        return query(sql: sql) { statement in
            sqlite3_bind_text(statement, 1, escaped, -1, sqliteTransient)
        }
    }

    private func searchDatabaseWithoutFTS(_ value: String) -> [ClipboardItem] {
        guard database != nil else {
            return ordered(items.filter {
                $0.text?.localizedCaseInsensitiveContains(value) == true
            })
        }
        let sql = """
        SELECT id, kind, text, image_path, created_at, source_bundle_id, pinned_at
        FROM items
        WHERE text IS NOT NULL AND instr(lower(text), lower(?)) > 0
        ORDER BY (pinned_at IS NULL), pinned_at ASC, created_at DESC
        LIMIT 500
        """
        return query(sql: sql) { statement in
            sqlite3_bind_text(statement, 1, value, -1, sqliteTransient)
        }
    }

    private func ordered(_ values: [ClipboardItem]) -> [ClipboardItem] {
        let pinned = values.filter(\.isPinned).sorted {
            ($0.pinnedAt ?? .distantFuture) < ($1.pinnedAt ?? .distantFuture)
        }
        return pinned + values.filter { !$0.isPinned }.sorted { $0.createdAt > $1.createdAt }
    }

    private func trimMemoryWindow() {
        let pinned = items.filter(\.isPinned)
        let recent = items.filter { !$0.isPinned }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(Self.memoryWindow)
        items = Array(pinned + recent)
    }

    private func bind(_ item: ClipboardItem, to statement: OpaquePointer) {
        bind(item.id.uuidString, to: statement, at: 1)
        bind(item.kind.rawValue, to: statement, at: 2)
        bind(item.text, to: statement, at: 3)
        bind(item.imagePath, to: statement, at: 4)
        sqlite3_bind_double(statement, 5, item.createdAt.timeIntervalSince1970)
        bind(item.sourceBundleID, to: statement, at: 6)
        if let pinnedAt = item.pinnedAt {
            sqlite3_bind_double(statement, 7, pinnedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 7)
        }
    }

    private func bind(_ value: String?, to statement: OpaquePointer, at index: Int32) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func query(
        sql: String,
        bind: (OpaquePointer) -> Void = { _ in }
    ) -> [ClipboardItem] {
        guard let statement = prepare(sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(statement)
        var values: [ClipboardItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let item = item(from: statement) { values.append(item) }
        }
        return values
    }

    private func item(from statement: OpaquePointer) -> ClipboardItem? {
        guard let idText = columnString(statement, 0),
              let id = UUID(uuidString: idText),
              let kindText = columnString(statement, 1),
              let kind = ClipboardItemKind(rawValue: kindText)
        else { return nil }
        let pinnedAt = sqlite3_column_type(statement, 6) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
        return ClipboardItem(
            id: id,
            kind: kind,
            text: columnString(statement, 2),
            imagePath: columnString(statement, 3),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
            sourceBundleID: columnString(statement, 5),
            pinnedAt: pinnedAt
        )
    }

    private func columnString(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index)
        else { return nil }
        return String(cString: value)
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        guard let database else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        return statement
    }

    private func execute(
        _ sql: String,
        textValues: [String] = [],
        doubleValue: Double? = nil
    ) {
        guard let statement = prepare(sql) else { return }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in textValues.enumerated() {
            sqlite3_bind_text(statement, Int32(offset + 1), value, -1, sqliteTransient)
        }
        if let doubleValue {
            sqlite3_bind_double(statement, 1, doubleValue)
        }
        sqlite3_step(statement)
    }

    @discardableResult
    private func executeRaw(_ sql: String) -> Bool {
        guard let database else { return false }
        return sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
    }

    private func closeDatabase() {
        if let database {
            sqlite3_close(database)
        }
        database = nil
        supportsTrigramSearch = false
    }

    private func deleteOwnedImage(for item: ClipboardItem) {
        guard let path = item.imagePath,
              path.hasPrefix(imagesDirectoryURL.path + "/")
        else { return }
        try? FileManager.default.removeItem(atPath: path)
    }
}
