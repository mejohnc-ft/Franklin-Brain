import Foundation

// This route is intentionally loopback-only. A remote Shortcut must use an SSH tunnel
// to 127.0.0.1:8765; exposing the legacy unauthenticated routes on a LAN is unsafe.
enum IPhoneIntake {
    static func accept(_ request: HTTPRequest) -> HTTPResponse {
        guard let configured = ProcessInfo.processInfo.environment["TERMINAL_BRAIN_IPHONE_TOKEN"],
              configured.utf8.count >= 32 else {
            return .json(503, ["ok": false, "error": "iPhone intake is disabled; configure TERMINAL_BRAIN_IPHONE_TOKEN (32+ bytes) before launching the app"])
        }
        let supplied = request.headers["authorization"] ?? ""
        guard secureEqual(supplied, "Bearer " + configured) else {
            return .json(401, ["ok": false, "error": "Unauthorized"])
        }
        guard request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true,
              let object = request.jsonBody,
              let content = object["content"] as? String else {
            return .json(400, ["ok": false, "error": "JSON content is required"])
        }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 8_192 else {
            return .json(400, ["ok": false, "error": "content must be 1–8192 bytes"])
        }
        let title = (object["title"] as? String ?? "iPhone Capture").trimmingCharacters(in: .whitespacesAndNewlines)
        let project = (object["project"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.utf8.count <= 120, project.utf8.count <= 120 else {
            return .json(400, ["ok": false, "error": "title or project too long"])
        }
        // Keep user-supplied fields out of YAML/frontmatter and Markdown structure.
        guard !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !project.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return .json(400, ["ok": false, "error": "title or project contains control characters"])
        }
        let quoted = text.components(separatedBy: .newlines).map { "> " + $0 }.joined(separator: "\n")
        // Do not permit untrusted Shortcut fields to alter source, tags, status or paths.
        let result = OracleSnapshot.commit(title: title.isEmpty ? "iPhone Capture" : title,
                                           content: quoted, question: "Captured from iPhone Shortcut",
                                           source: "iPhone Shortcut", project: project,
                                           tags: ["iphone", "inbox"])
        return .json(result["ok"] as? Bool == true ? 200 : 500, result)
    }

    private static func secureEqual(_ a: String, _ b: String) -> Bool {
        let lhs = Array(a.utf8), rhs = Array(b.utf8)
        var difference = lhs.count ^ rhs.count
        for index in 0..<max(lhs.count, rhs.count) {
            difference |= Int((index < lhs.count ? lhs[index] : 0) ^ (index < rhs.count ? rhs[index] : 0))
        }
        return difference == 0
    }
}
