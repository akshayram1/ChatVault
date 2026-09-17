import Foundation

enum SourceFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case cursor
    case claude
    case codex

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .cursor: return "Cursor"
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    func matches(_ source: ChatSource) -> Bool {
        switch self {
        case .all: return true
        case .cursor: return source == .cursor
        case .claude: return source == .claude
        case .codex: return source == .codex
        }
    }
}

enum ChatSource: String, CaseIterable, Identifiable, Hashable {
    case cursor
    case claude
    case codex

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cursor: return "Cursor"
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}

struct ChatSession: Identifiable, Hashable {
    var id: String { "\(source.rawValue):\(sessionId):\(path.path)" }
    let sessionId: String
    let source: ChatSource
    var title: String
    var firstPrompt: String
    let path: URL
    var project: String
    var created: Date
    var updated: Date
    var isSubagent: Bool
}

struct GrepHit: Identifiable, Hashable {
    let id = UUID()
    let line: Int
    let role: String
    let text: String
}

enum AccessKind: String, CaseIterable, Identifiable {
    case cursor
    case cursorDB
    case claude
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cursor: return "Cursor chats"
        case .cursorDB: return "Cursor titles"
        case .claude: return "Claude Code chats"
        case .codex: return "Codex chats"
        }
    }

    var detail: String {
        switch self {
        case .cursor: return "~/.cursor/projects"
        case .cursorDB: return "Cursor Application Support database"
        case .claude: return "~/.claude/projects"
        case .codex: return "~/.codex/sessions"
        }
    }
}

enum AccessStatus: Equatable {
    case granted
    case missing
    case denied
}
