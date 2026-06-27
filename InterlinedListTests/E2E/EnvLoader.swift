import Foundation

/// Loads credentials for E2E tests from (in order of precedence):
///   1. Process environment (set in the Xcode scheme's Test action env vars, or CI)
///   2. A `.env` file at the repository root (gitignored, for local dev)
///
/// Returns `nil` if neither source has the key — callers should then `XCTSkip`
/// so the suite doesn't fail in environments without credentials.
enum EnvLoader {
    static let emailKey = "INTERLINEDLIST_EMAIL"
    static let passwordKey = "INTERLINEDLIST_PASSWORD"

    static func value(for key: String) -> String? {
        if let env = ProcessInfo.processInfo.environment[key], !env.isEmpty {
            return env
        }
        return dotEnv[key]
    }

    static var email: String? { value(for: emailKey) }
    static var password: String? { value(for: passwordKey) }

    static var hasCredentials: Bool {
        email != nil && password != nil
    }

    private static let dotEnv: [String: String] = {
        guard let url = dotEnvURL,
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }
        var result: [String: String] = [:]
        for line in raw.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
            let valueRaw = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            let value = unquote(String(valueRaw))
            result[String(key)] = value
        }
        return result
    }()

    /// Walks up from this source file's path to find the repository root
    /// (the directory containing `.env`).
    private static var dotEnvURL: URL? {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent(".env")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    private static func unquote(_ s: String) -> String {
        if s.count >= 2,
           (s.first == "\"" && s.last == "\"") || (s.first == "'" && s.last == "'") {
            return String(s.dropFirst().dropLast())
        }
        return s
    }
}
