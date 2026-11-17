import Foundation
import SQLite3
import SwiftUI

@MainActor
final class CatalogStore: ObservableObject {
    @Published var groups: [String] = []
    @Published var items: [MediaItem] = []
    @Published var selectedCategory: MediaKind = .all
    @Published var searchQuery: String = ""
    @Published var isSearching: Bool = false
    @Published var isSyncing: Bool = false
    @Published var statusText: String = "Pronto"
    @Published var totalCount: Int = 0

    private var db: OpaquePointer?
    private let dbPath: String
    private let lastSyncKey = "tessytv_last_m3u_sync_date"
    private let savedUrlKey = "tessytv_saved_m3u_url"

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.dbPath = docs.appendingPathComponent("tessytv_catalog.sqlite").path
        openDatabase()
        refreshCountAndGroups()
        scheduleDailySyncIfNeeded()
    }

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            let createSQL = """
            CREATE TABLE IF NOT EXISTS channels (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                grp TEXT NOT NULL,
                title TEXT NOT NULL,
                url TEXT NOT NULL,
                kind TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_channels_title ON channels(title);
            CREATE INDEX IF NOT EXISTS idx_channels_grp ON channels(grp);
            CREATE INDEX IF NOT EXISTS idx_channels_kind ON channels(kind);
            """
            sqlite3_exec(db, createSQL, nil, nil, nil)
        }
    }

    func scheduleDailySyncIfNeeded() {
        guard let url = UserDefaults.standard.string(forKey: savedUrlKey), !url.isEmpty else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        if UserDefaults.standard.string(forKey: lastSyncKey) == today {
            return
        }
        Task {
            await importFromURL(urlString: url, silent: true)
        }
    }

    func importFromURL(urlString: String, silent: Bool = false) async {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        UserDefaults.standard.set(url.absoluteString, forKey: savedUrlKey)
        isSyncing = true
        statusText = "Aggiorno lista canali..."

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                let inserted = await Task.detached(priority: .userInitiated) { [dbPath] in
                    Self.parseAndInsertM3U(content: text, dbPath: dbPath)
                }.value

                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                UserDefaults.standard.set(formatter.string(from: Date()), forKey: lastSyncKey)

                refreshCountAndGroups()
                statusText = "Lista aggiornata (\(inserted) elementi)"
            }
        } catch {
            if !silent {
                statusText = "Errore aggiornamento: \(error.localizedDescription)"
            }
        }
        isSyncing = false
    }

    func clearCatalog() {
        sqlite3_exec(db, "DELETE FROM channels;", nil, nil, nil)
        UserDefaults.standard.removeObject(forKey: lastSyncKey)
        groups = []
        items = []
        totalCount = 0
        statusText = "Lista rimossa."
    }

    func performSearch() {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let cat = selectedCategory
        isSearching = true

        Task {
            let results = await Task.detached(priority: .userInitiated) { [dbPath] in
                Self.queryChannels(dbPath: dbPath, category: cat, query: q, limit: q.isEmpty ? 300 : 1500)
            }.value

            self.items = results
            self.isSearching = false
            self.statusText = q.isEmpty
                ? "Mostrati \(totalCount) elementi (\(cat.rawValue))."
                : "Trovati \(results.count) risultati per '\(q)'."
        }
    }

    func itemsForGroup(_ groupName: String) -> [MediaItem] {
        let cat = selectedCategory
        return Self.queryChannelsByGroup(dbPath: dbPath, group: groupName, category: cat)
    }

    private func refreshCountAndGroups() {
        var countStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM channels;", -1, &countStmt, nil) == SQLITE_OK {
            if sqlite3_step(countStmt) == SQLITE_ROW {
                totalCount = Int(sqlite3_column_int(countStmt, 0))
            }
        }
        sqlite3_finalize(countStmt)

        var grpList: [String] = []
        var grpStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT DISTINCT grp FROM channels ORDER BY grp COLLATE NOCASE ASC;", -1, &grpStmt, nil) == SQLITE_OK {
            while sqlite3_step(grpStmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(grpStmt, 0) {
                    grpList.append(String(cString: cStr))
                }
            }
        }
        sqlite3_finalize(grpStmt)
        groups = grpList
        statusText = "Mostrati \(totalCount) elementi (\(selectedCategory.rawValue))."
    }

    nonisolated private static func parseAndInsertM3U(content: String, dbPath: String) -> Int {
        var localDB: OpaquePointer?
        guard sqlite3_open(dbPath, &localDB) == SQLITE_OK else { return 0 }
        defer { sqlite3_close(localDB) }

        sqlite3_exec(localDB, "BEGIN TRANSACTION;", nil, nil, nil)
        sqlite3_exec(localDB, "DELETE FROM channels;", nil, nil, nil)

        var insertStmt: OpaquePointer?
        sqlite3_prepare_v2(localDB, "INSERT INTO channels (grp, title, url, kind) VALUES (?, ?, ?, ?);", -1, &insertStmt, nil)

        var currentGroup = "Generale"
        var currentTitle = ""
        var count = 0

        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#EXTINF:") {
                if let grpRange = trimmed.range(of: "group-title=\"") {
                    let rest = trimmed[grpRange.upperBound...]
                    if let endQuote = rest.firstIndex(of: "\"") {
                        currentGroup = String(rest[..<endQuote])
                    }
                }
                if let commaIdx = trimmed.lastIndex(of: ",") {
                    currentTitle = String(trimmed[trimmed.index(after: commaIdx)...]).trimmingCharacters(in: .whitespaces)
                }
            } else if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                let lowUrl = trimmed.lowercased()
                let lowGrp = currentGroup.lowercased()
                let kind: String
                if lowUrl.contains("/series/") || lowGrp.contains("serie") {
                    kind = MediaKind.series.rawValue
                } else if lowUrl.contains("/movie/") || lowGrp.contains("vod") || lowGrp.contains("film") {
                    kind = MediaKind.vod.rawValue
                } else {
                    kind = MediaKind.live.rawValue
                }

                sqlite3_reset(insertStmt)
                sqlite3_bind_text(insertStmt, 1, (currentGroup as NSString).utf8String, -1, nil)
                sqlite3_bind_text(insertStmt, 2, (currentTitle as NSString).utf8String, -1, nil)
                sqlite3_bind_text(insertStmt, 3, (trimmed as NSString).utf8String, -1, nil)
                sqlite3_bind_text(insertStmt, 4, (kind as NSString).utf8String, -1, nil)
                if sqlite3_step(insertStmt) == SQLITE_DONE {
                    count += 1
                }
            }
        }

        sqlite3_finalize(insertStmt)
        sqlite3_exec(localDB, "COMMIT;", nil, nil, nil)
        return count
    }

    nonisolated private static func queryChannels(dbPath: String, category: MediaKind, query: String, limit: Int) -> [MediaItem] {
        var localDB: OpaquePointer?
        guard sqlite3_open(dbPath, &localDB) == SQLITE_OK else { return [] }
        defer { sqlite3_close(localDB) }

        var sql = "SELECT id, grp, title, url, kind FROM channels WHERE 1=1"
        if category != .all {
            sql += " AND kind = '\(category.rawValue)'"
        }
        if !query.isEmpty {
            let safeQ = query.replacingOccurrences(of: "'", with: "''")
            sql += " AND (title LIKE '%\(safeQ)%' OR grp LIKE '%\(safeQ)%')"
        }
        sql += " LIMIT \(limit);"

        var results: [MediaItem] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(localDB, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let grp = String(cString: sqlite3_column_text(stmt, 1))
                let title = String(cString: sqlite3_column_text(stmt, 2))
                let url = String(cString: sqlite3_column_text(stmt, 3))
                let kindStr = String(cString: sqlite3_column_text(stmt, 4))
                results.append(MediaItem(id: id, group: grp, title: title, url: url, kind: MediaKind(rawValue: kindStr) ?? .live))
            }
        }
        sqlite3_finalize(stmt)
        return results
    }

    nonisolated private static func queryChannelsByGroup(dbPath: String, group: String, category: MediaKind) -> [MediaItem] {
        var localDB: OpaquePointer?
        guard sqlite3_open(dbPath, &localDB) == SQLITE_OK else { return [] }
        defer { sqlite3_close(localDB) }

        let safeGrp = group.replacingOccurrences(of: "'", with: "''")
        var sql = "SELECT id, grp, title, url, kind FROM channels WHERE grp = '\(safeGrp)'"
        if category != .all {
            sql += " AND kind = '\(category.rawValue)'"
        }
        sql += " ORDER BY title COLLATE NOCASE ASC;"

        var results: [MediaItem] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(localDB, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let grp = String(cString: sqlite3_column_text(stmt, 1))
                let title = String(cString: sqlite3_column_text(stmt, 2))
                let url = String(cString: sqlite3_column_text(stmt, 3))
                let kindStr = String(cString: sqlite3_column_text(stmt, 4))
                results.append(MediaItem(id: id, group: grp, title: title, url: url, kind: MediaKind(rawValue: kindStr) ?? .live))
            }
        }
        sqlite3_finalize(stmt)
        return results
    }
}
