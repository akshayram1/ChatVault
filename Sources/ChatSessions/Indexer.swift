import Foundation
import SQLite3

enum SessionIndexer {
    struct Roots: Sendable {
        var cursorProjects: URL?
        var cursorDB: URL?
        var claudeProjects: URL?
        var codexRoot: URL?
        var includeSubagents: Bool
    }

    static func scan(roots: Roots, progress: @escaping @Sendable (String) -> Void = { _ in }) -> [ChatSession] {
        var sessions: [ChatSession] = []
        if let cursor = roots.cursorProjects {
            progress("Reading Cursor chats…")
            sessions.append(contentsOf: scanCursor(root: cursor, db: roots.cursorDB, includeSubagents: roots.includeSubagents))
        }
        if let claude = roots.claudeProjects {
            progress("Reading Claude Code chats…")
            sessions.append(contentsOf: scanClaude(root: claude, includeSubagents: roots.includeSubagents))
        }
        if let codex = roots.codexRoot {
            progress("Reading Codex chats…")
            sessions.append(contentsOf: scanCodex(root: codex))
        }
        sessions.sort { $0.updated > $1.updated }
        return sessions
    }

    static func grep(path: URL, pattern: String, maxMatches: Int = 40) -> [GrepHit] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        guard let handle = try? FileHandle(forReadingFrom: path) else { return [] }
        defer { try? handle.close() }
        var hits: [GrepHit] = []
        var leftover = Data()
        var lineNo = 0
        while true {
            let chunk = handle.readData(ofLength: 256 * 1024)
            if chunk.isEmpty && leftover.isEmpty { break }
            leftover.append(chunk)
            let parts = leftover.split(separator: 10, omittingEmptySubsequences: false) // \n
            if chunk.isEmpty {
                leftover = Data()
            } else if let last = parts.last {
                leftover = Data(last)
            }
            let complete = chunk.isEmpty ? parts : parts.dropLast()
            for part in complete {
                lineNo += 1
                guard let line = String(data: Data(part), encoding: .utf8) else { continue }
                let range = NSRange(line.startIndex..., in: line)
                guard regex.firstMatch(in: line, range: range) != nil else { continue }
                let obj = TextExtract.parseJSON(line)
                var role = obj?["role"] as? String ?? ""
                if role.isEmpty, let type = obj?["type"] as? String, ["user", "assistant"].contains(type) {
                    role = type
                }
                let payload = obj?["payload"] as? [String: Any] ?? [:]
                if let pRole = payload["role"] as? String { role = pRole }
                var text = TextExtract.cleanUser(
                    TextExtract.extract(obj?["message"] ?? payload["content"] ?? obj?["content"])
                )
                if text.isEmpty { text = line }
                hits.append(GrepHit(line: lineNo, role: role, text: TextExtract.clip(text, 500)))
                if hits.count >= maxMatches { return hits }
            }
            if chunk.isEmpty { break }
        }
        return hits
    }

    private static func scanCursor(root: URL, db: URL?, includeSubagents: Bool) -> [ChatSession] {
        let headers = db.map { loadCursorHeaders(db: $0) } ?? [:]
        let workspaces = db.map { loadCursorWorkspaces(db: $0) } ?? [:]
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        var out: [ChatSession] = []
        for projectDir in projects {
            let transcripts = projectDir.appendingPathComponent("agent-transcripts")
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: transcripts.path, isDirectory: &isDir), isDir.boolValue else { continue }
            guard let chats = try? fm.contentsOfDirectory(at: transcripts, includingPropertiesForKeys: nil) else { continue }
            for chatDir in chats {
                let jsonl = chatDir.appendingPathComponent("\(chatDir.lastPathComponent).jsonl")
                if let session = cursorSession(jsonl: jsonl, headers: headers, workspaces: workspaces, fallbackProject: projectDir.lastPathComponent, isSub: false) {
                    out.append(session)
                }
                if includeSubagents {
                    let sub = chatDir.appendingPathComponent("subagents")
                    if let subs = try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil) {
                        for subDir in subs {
                            let subJsonl = subDir.appendingPathComponent("\(subDir.lastPathComponent).jsonl")
                            if let session = cursorSession(jsonl: subJsonl, headers: headers, workspaces: workspaces, fallbackProject: projectDir.lastPathComponent, isSub: true) {
                                out.append(session)
                            }
                        }
                    }
                }
            }
        }
        return out
    }

    private static func cursorSession(
        jsonl: URL,
        headers: [String: (title: String, created: Date?, updated: Date?, workspace: String, isSub: Bool)],
        workspaces: [String: String],
        fallbackProject: String,
        isSub: Bool
    ) -> ChatSession? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: jsonl.path) else { return nil }
        guard let attrs = try? fm.attributesOfItem(atPath: jsonl.path),
              let size = attrs[.size] as? NSNumber, size.intValue > 2
        else { return nil }
        let sid = jsonl.deletingPathExtension().lastPathComponent
        let objects = TextExtract.iterateJSONL(jsonl, maxBytes: 256_000, maxLines: 24)
        let first = TextExtract.firstUserPrompt(from: objects, source: .cursor)
        let meta = headers[sid]
        let mtime = (attrs[.modificationDate] as? Date) ?? Date.distantPast
        let title = nonEmpty(meta?.title) ?? TextExtract.clip(first, 80)
        let project: String
        if let wid = meta?.workspace, let mapped = workspaces[wid], !mapped.isEmpty {
            project = mapped.replacingOccurrences(of: "file://", with: "")
        } else {
            project = fallbackProject
        }
        return ChatSession(
            sessionId: sid,
            source: .cursor,
            title: title.isEmpty ? sid : title,
            firstPrompt: TextExtract.clip(first, 280),
            path: jsonl,
            project: project,
            created: meta?.created ?? mtime,
            updated: meta?.updated ?? mtime,
            isSubagent: meta?.isSub ?? isSub
        )
    }

    private static func scanClaude(root: URL, includeSubagents: Bool) -> [ChatSession] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        var out: [ChatSession] = []
        for folder in folders {
            let jsonls = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for jsonl in jsonls where jsonl.pathExtension == "jsonl" {
                if let session = claudeSession(jsonl: jsonl, isSub: false) {
                    out.append(session)
                }
            }
            if includeSubagents {
                let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: nil)
                while let item = enumerator?.nextObject() as? URL {
                    if item.pathExtension == "jsonl", item.path.contains("/subagents/"), item != folder {
                        if let session = claudeSession(jsonl: item, isSub: true) {
                            out.append(session)
                        }
                    }
                }
            }
        }
        return out
    }

    private static func claudeSession(jsonl: URL, isSub: Bool) -> ChatSession? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: jsonl.path),
              let size = attrs[.size] as? NSNumber, size.intValue > 2
        else { return nil }
        let objects = TextExtract.iterateJSONL(jsonl, maxBytes: 256_000, maxLines: 60)
        let first = TextExtract.firstUserPrompt(from: objects, source: .claude)
        var cwd = ""
        var created: Date?
        for obj in objects {
            if cwd.isEmpty, let value = obj["cwd"] as? String { cwd = value }
            if created == nil, let stamp = obj["timestamp"] as? String {
                created = parseISO(stamp)
            }
        }
        let mtime = (attrs[.modificationDate] as? Date) ?? Date.distantPast
        let sid = jsonl.deletingPathExtension().lastPathComponent
        return ChatSession(
            sessionId: sid,
            source: .claude,
            title: TextExtract.clip(first, 80).isEmpty ? sid : TextExtract.clip(first, 80),
            firstPrompt: TextExtract.clip(first, 280),
            path: jsonl,
            project: cwd,
            created: created ?? mtime,
            updated: mtime,
            isSubagent: isSub
        )
    }

    private static func scanCodex(root: URL) -> [ChatSession] {
        let titles = loadCodexTitles(root.appendingPathComponent("session_index.jsonl"))
        let sessionsRoot = root.appendingPathComponent("sessions")
        let fm = FileManager.default
        let enumerator = fm.enumerator(at: sessionsRoot, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
        var out: [ChatSession] = []
        while let item = enumerator?.nextObject() as? URL {
            guard item.pathExtension == "jsonl" else { continue }
            guard let attrs = try? fm.attributesOfItem(atPath: item.path),
                  let size = attrs[.size] as? NSNumber, size.intValue > 2
            else { continue }
            let objects = TextExtract.iterateJSONL(item, maxBytes: 400_000, maxLines: 80)
            var sid = item.deletingPathExtension().lastPathComponent
            var cwd = ""
            var created: Date?
            if let meta = objects.first, meta["type"] as? String == "session_meta" {
                let payload = meta["payload"] as? [String: Any] ?? [:]
                if let value = (payload["id"] as? String) ?? (payload["session_id"] as? String) {
                    sid = value
                }
                cwd = payload["cwd"] as? String ?? ""
                created = parseISO(payload["timestamp"] as? String ?? meta["timestamp"] as? String)
            }
            let first = TextExtract.firstUserPrompt(from: objects, source: .codex)
            let mtime = (attrs[.modificationDate] as? Date) ?? Date.distantPast
            let title = titles[sid]?.title ?? TextExtract.clip(first, 80)
            out.append(
                ChatSession(
                    sessionId: sid,
                    source: .codex,
                    title: title.isEmpty ? sid : title,
                    firstPrompt: TextExtract.clip(first, 280),
                    path: item,
                    project: cwd,
                    created: created ?? mtime,
                    updated: titles[sid]?.updated ?? mtime,
                    isSubagent: false
                )
            )
        }
        return out
    }

    private static func loadCodexTitles(_ url: URL) -> [String: (title: String, updated: Date?)] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: (title: String, updated: Date?)] = [:]
        for line in text.split(separator: "\n") {
            guard let obj = TextExtract.parseJSON(String(line)),
                  let id = obj["id"] as? String
            else { continue }
            out[id] = (
                title: obj["thread_name"] as? String ?? "",
                updated: parseISO(obj["updated_at"] as? String)
            )
        }
        return out
    }

    private static func loadCursorHeaders(db: URL) -> [String: (title: String, created: Date?, updated: Date?, workspace: String, isSub: Bool)] {
        guard let sqlite = openSQLite(db) else { return [:] }
        defer { sqlite3_close(sqlite) }
        let sql = "SELECT composerId, workspaceId, createdAt, lastUpdatedAt, isSubagent, json_extract(value,'$.name') FROM composerHeaders"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(sqlite, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }
        var out: [String: (title: String, created: Date?, updated: Date?, workspace: String, isSub: Bool)] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = columnString(stmt, 0)
            if id.isEmpty { continue }
            out[id] = (
                title: columnString(stmt, 5),
                created: dateFromMS(sqlite3_column_int64(stmt, 2)),
                updated: dateFromMS(sqlite3_column_int64(stmt, 3)),
                workspace: columnString(stmt, 1),
                isSub: sqlite3_column_int(stmt, 4) != 0
            )
        }
        return out
    }

    private static func loadCursorWorkspaces(db: URL) -> [String: String] {
        var mapping: [String: String] = [:]
        if let sqlite = openSQLite(db) {
            defer { sqlite3_close(sqlite) }
            let sql = "SELECT value FROM ItemTable WHERE key = 'workspaceMetadata.entries'"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(sqlite, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    let raw = columnString(stmt, 0)
                    if let data = raw.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let entries = obj["entries"] as? [[String: Any]]
                    {
                        for entry in entries {
                            if let wid = entry["workspaceId"] as? String {
                                let uri = (entry["folderUri"] as? String ?? "").replacingOccurrences(of: "file://", with: "")
                                if !uri.isEmpty { mapping[wid] = uri }
                            }
                        }
                    }
                }
                sqlite3_finalize(stmt)
            }
        }
        let storage = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage")
        if let folders = try? FileManager.default.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil) {
            for folder in folders {
                if mapping[folder.lastPathComponent] != nil { continue }
                let meta = folder.appendingPathComponent("workspace.json")
                guard let data = try? Data(contentsOf: meta),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let folderUri = obj["folder"] as? String
                else { continue }
                mapping[folder.lastPathComponent] = folderUri.replacingOccurrences(of: "file://", with: "")
            }
        }
        return mapping
    }

    private static func openSQLite(_ url: URL) -> OpaquePointer? {
        var db: OpaquePointer?
        let uri = "file:\(url.path)?mode=ro"
        if sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK {
            return db
        }
        sqlite3_close(db)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("chat-sessions-\(UUID().uuidString).vscdb")
        do {
            try FileManager.default.copyItem(at: url, to: tmp)
        } catch {
            return nil
        }
        db = nil
        if sqlite3_open_v2(tmp.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
            return db
        }
        sqlite3_close(db)
        return nil
    }

    private static func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let stmt, let cstr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cstr)
    }

    private static func dateFromMS(_ ms: sqlite3_int64) -> Date? {
        guard ms > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
    }

    private static func parseISO(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
