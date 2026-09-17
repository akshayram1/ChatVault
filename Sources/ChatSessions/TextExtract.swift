import Foundation

enum TextExtract {
    private static let userQuery =
        try! NSRegularExpression(pattern: #"<user_query>\s*(.*?)\s*</user_query>"#, options: [.dotMatchesLineSeparators])
    private static let timestamp =
        try! NSRegularExpression(pattern: #"<timestamp>.*?</timestamp>"#, options: [.dotMatchesLineSeparators])

    private static let noisePrefixes = [
        "<recommended_plugins>",
        "<skills_instructions>",
        "<environment_context>",
        "<user_instructions>",
        "<mcp_instructions>",
        "<developer_instructions>",
        "<agent_skills>",
        "<available_skills>",
        "<available_subagent_types>",
        "<user_info>",
        "<system-reminder>",
    ]

    static func clip(_ text: String, _ limit: Int = 240) -> String {
        let collapsed = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= limit { return collapsed }
        return String(collapsed.prefix(limit - 1)) + "…"
    }

    static func cleanUser(_ raw: String) -> String {
        var text = raw
        let full = NSRange(text.startIndex..., in: text)
        if let match = userQuery.firstMatch(in: text, range: full),
           let range = Range(match.range(at: 1), in: text)
        {
            text = String(text[range])
        }
        text = timestamp.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isNoise(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return noisePrefixes.contains { trimmed.hasPrefix($0) }
    }

    static func extract(_ value: Any?) -> String {
        guard let value else { return "" }
        if let text = value as? String { return text }
        if let dict = value as? [String: Any] {
            if let text = dict["text"] { return extract(text) }
            if let content = dict["content"] { return extract(content) }
            return ""
        }
        if let array = value as? [Any] {
            return array.compactMap { item -> String? in
                guard let dict = item as? [String: Any] else {
                    return item as? String
                }
                let type = dict["type"] as? String
                if ["text", "input_text", "output_text"].contains(type) {
                    return dict["text"] as? String
                }
                if type != "tool_use" && type != "tool_result", dict["text"] != nil {
                    return dict["text"] as? String
                }
                return nil
            }.filter { !$0.isEmpty }.joined(separator: "\n")
        }
        return ""
    }

    static func parseJSON(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func iterateJSONL(_ url: URL, maxBytes: Int = 512_000, maxLines: Int = 80) -> [[String: Any]] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: maxBytes)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return []
        }
        var out: [[String: Any]] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if out.count >= maxLines { break }
            if let obj = parseJSON(String(line)) {
                out.append(obj)
            }
        }
        return out
    }

    static func firstUserPrompt(from objects: [[String: Any]], source: ChatSource) -> String {
        for obj in objects {
            let text: String
            switch source {
            case .cursor:
                guard obj["role"] as? String == "user" else { continue }
                text = cleanUser(extract(obj["message"]))
            case .claude:
                guard obj["type"] as? String == "user" else { continue }
                text = cleanUser(extract(obj["message"]))
            case .codex:
                let payload = obj["payload"] as? [String: Any] ?? [:]
                guard payload["role"] as? String == "user" || obj["role"] as? String == "user" else { continue }
                text = cleanUser(extract(payload["content"] ?? obj["content"]))
            }
            if !text.isEmpty && !isNoise(text) { return text }
        }
        return ""
    }
}
