import Foundation

// 熱詞 / 提示詞：把你常用的技術術語餵給 Whisper，讓它更會辨識程式相關的詞。
//
// Whisper 支援「prompt」機制：在解碼前先給它一段文字當上下文，模型就更傾向
// 拼出這些詞（例如 useEffect、pnpm、Tailwind、你的 repo 名、變數名）。
//
// 來源：~/.vibevoice/hotwords.txt（一行一個詞，# 開頭為註解）。
// 檔案不存在時用下面這份預設清單。你可以隨時編輯，下次辨識即生效。
enum Vocabulary {
    static let defaults: [String] = [
        "TypeScript", "JavaScript", "Python", "Swift", "React", "Vue", "Node.js",
        "useEffect", "useState", "async", "await", "refactor", "function", "const",
        "pnpm", "npm", "Vite", "Tailwind", "Electron", "Xcode", "WhisperKit",
        "Claude Code", "commit", "rebase", "merge", "pull request", "endpoint",
        "API", "JSON", "TODO", "bug", "deploy", "Docker", "localhost",
    ]

    private static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".vibevoice/hotwords.txt")
    }

    static func load() -> [String] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return defaults
        }
        let words = content
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return words.isEmpty ? defaults : words
    }

    // 組成給 Whisper 的 prompt 字串（逗號分隔即可）。
    static func promptText() -> String {
        load().joined(separator: ", ")
    }
}
