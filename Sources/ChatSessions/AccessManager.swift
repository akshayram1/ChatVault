import AppKit
import Foundation

final class AccessManager: ObservableObject {
    @Published var consented = false
    @Published var status: [AccessKind: AccessStatus] = [:]
    @Published var lastError: String?

    private let defaults = UserDefaults.standard
    private let consentKey = "chatSessions.consented"
    private var bookmarkKeys: [AccessKind: String] {
        [
            .cursor: "chatSessions.bookmark.cursor",
            .cursorDB: "chatSessions.bookmark.cursorDB",
            .claude: "chatSessions.bookmark.claude",
            .codex: "chatSessions.bookmark.codex",
        ]
    }

    private var heldURLs: [AccessKind: URL] = [:]

    init() {
        consented = defaults.bool(forKey: consentKey)
        restoreBookmarks()
        refreshStatus()
    }

    static func defaultURL(for kind: AccessKind, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        switch kind {
        case .cursor:
            return home.appendingPathComponent(".cursor/projects")
        case .cursorDB:
            return home
                .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        case .claude:
            return home.appendingPathComponent(".claude/projects")
        case .codex:
            return home.appendingPathComponent(".codex")
        }
    }

    func url(for kind: AccessKind) -> URL {
        heldURLs[kind] ?? Self.defaultURL(for: kind)
    }

    func grantConsent() {
        consented = true
        defaults.set(true, forKey: consentKey)
        refreshStatus()
    }

    func resetConsent() {
        consented = false
        defaults.set(false, forKey: consentKey)
        for kind in AccessKind.allCases {
            defaults.removeObject(forKey: bookmarkKeys[kind]!)
        }
        heldURLs.removeAll()
        refreshStatus()
    }

    func refreshStatus() {
        var next: [AccessKind: AccessStatus] = [:]
        for kind in AccessKind.allCases {
            next[kind] = probe(kind)
        }
        status = next
    }

    func allReadableOrMissing() -> Bool {
        AccessKind.allCases.allSatisfy { kind in
            let state = status[kind] ?? .denied
            return state != .denied
        }
    }

    func requestAccess(for kind: AccessKind) {
        let starting = Self.defaultURL(for: kind)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = kind != .cursorDB
        panel.canChooseFiles = kind == .cursorDB
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = kind == .cursorDB ? starting.deletingLastPathComponent() : starting
        panel.message = "Allow Chat Sessions to read \(kind.title). Files stay on this Mac."
        panel.prompt = "Grant Access"
        panel.title = "Grant \(kind.title)"
        guard panel.runModal() == .OK, let picked = panel.url else { return }
        storeBookmark(picked, for: kind)
        refreshStatus()
    }

    func requestHomeFolderAccess() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.message = "Select your Home folder so Chat Sessions can read Cursor, Claude Code, and Codex chats already stored on this Mac."
        panel.prompt = "Grant Access"
        panel.title = "Allow access to Home"
        guard panel.runModal() == .OK, let home = panel.url else { return }
        storeBookmark(home.appendingPathComponent(".cursor/projects"), for: .cursor)
        storeBookmark(
            home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb"),
            for: .cursorDB
        )
        storeBookmark(home.appendingPathComponent(".claude/projects"), for: .claude)
        storeBookmark(home.appendingPathComponent(".codex"), for: .codex)
        refreshStatus()
    }

    func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
            ?? URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    private func probe(_ kind: AccessKind) -> AccessStatus {
        let target = url(for: kind)
        let fm = FileManager.default
        if kind == .cursorDB {
            if fm.isReadableFile(atPath: target.path) { return .granted }
            if fm.fileExists(atPath: target.path) { return .denied }
            return .missing
        }
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: target.path, isDirectory: &isDir) {
            return .missing
        }
        do {
            _ = try fm.contentsOfDirectory(atPath: target.path)
            return .granted
        } catch {
            return .denied
        }
    }

    private func restoreBookmarks() {
        for kind in AccessKind.allCases {
            guard let data = defaults.data(forKey: bookmarkKeys[kind]!) else { continue }
            var stale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                )
                _ = url.startAccessingSecurityScopedResource()
                heldURLs[kind] = url
                if stale {
                    storeBookmark(url, for: kind)
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func storeBookmark(_ url: URL, for kind: AccessKind) {
        _ = url.startAccessingSecurityScopedResource()
        heldURLs[kind] = url
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(data, forKey: bookmarkKeys[kind]!)
        } catch {
            lastError = error.localizedDescription
        }
    }
}
