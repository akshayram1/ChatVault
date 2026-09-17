import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var access = AccessManager()
    @Published var sessions: [ChatSession] = []
    @Published var isScanning = false
    @Published var progress = ""
    @Published var query = ""
    @Published var sourceFilter: SourceFilter = .all
    @Published var includeSubagents = false
    @Published var selectedID: String?
    @Published var grepPattern = ""
    @Published var grepHits: [GrepHit] = []
    @Published var isGrepping = false
    @Published var showPermissions = false

    var blockedFolders: [AccessKind] {
        AccessKind.allCases.filter { access.status[$0] == .denied }
    }

    private let relative = RelativeDateTimeFormatter()
    private let hasLaunchedKey = "chatVault.hasLaunchedBefore"

    init() {
        relative.unitsStyle = .abbreviated
        access.grantConsent()
        let isFirstLaunch = !UserDefaults.standard.bool(forKey: hasLaunchedKey)
        UserDefaults.standard.set(true, forKey: hasLaunchedKey)
        if isFirstLaunch {
            showPermissions = true
        }
        Task { await scan() }
    }

    var selected: ChatSession? {
        sessions.first { $0.id == selectedID }
    }

    var filtered: [ChatSession] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return sessions.filter { session in
            guard sourceFilter == .all || sourceFilter.matches(session.source) else { return false }
            if !includeSubagents && session.isSubagent { return false }
            guard !q.isEmpty else { return true }
            return [
                session.title,
                session.firstPrompt,
                session.project,
                session.sessionId,
                session.source.label,
            ].joined(separator: " ").lowercased().contains(q)
        }
    }

    func scan() async {
        isScanning = true
        progress = "Scanning…"
        access.refreshStatus()
        let roots = SessionIndexer.Roots(
            cursorProjects: access.status[.cursor] == .granted ? access.url(for: .cursor) : nil,
            cursorDB: access.status[.cursorDB] == .granted ? access.url(for: .cursorDB) : nil,
            claudeProjects: access.status[.claude] == .granted ? access.url(for: .claude) : nil,
            codexRoot: access.status[.codex] == .granted ? access.url(for: .codex) : nil,
            includeSubagents: includeSubagents
        )
        let result = await Task.detached(priority: .userInitiated) {
            SessionIndexer.scan(roots: roots)
        }.value
        sessions = result
        if selectedID == nil {
            selectedID = result.first?.id
        }
        isScanning = false
        progress = result.isEmpty ? "No chats found" : "\(result.count) chats"
    }

    func grepSelected() {
        guard let session = selected else { return }
        let pattern = grepPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else {
            grepHits = []
            return
        }
        isGrepping = true
        let path = session.path
        Task {
            let hits = await Task.detached(priority: .userInitiated) {
                SessionIndexer.grep(path: path, pattern: pattern)
            }.value
            grepHits = hits
            isGrepping = false
        }
    }

    func copyPath(_ session: ChatSession) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.path.path, forType: .string)
    }

    func reveal(_ session: ChatSession) {
        NSWorkspace.shared.activateFileViewerSelecting([session.path])
    }

    func format(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) || cal.isDateInYesterday(date) {
            return relative.localizedString(for: date, relativeTo: Date())
        }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}
