import Foundation

enum AppBias {
    case coding
    case writing
    case browser
    case general
}

struct AppDetector {
    static func bias(for bundleID: String, windowTitle: String) -> AppBias {
        switch bundleID {
        // IDEs and code editors
        case "com.todesktop.230313mzl4w4u92",   // Cursor
             "com.microsoft.VSCode",
             "com.apple.dt.Xcode",
             "com.jetbrains.intellij",
             "com.sublimetext.4",
             "com.panic.Nova",
             "io.zed.zed":
            return .coding

        // Terminals (assume coding context)
        case "com.apple.Terminal",
             "com.googlecode.iterm2",
             "com.github.wez.wezterm",
             "net.kovidgoyal.kitty":
            return .coding

        // Browsers — infer from window title
        case "com.apple.Safari",
             "org.mozilla.firefox",
             "com.google.Chrome",
             "com.brave.Browser":
            return browserBias(from: windowTitle)

        // Writing tools
        case "com.apple.Notes",
             "md.obsidian",
             "com.notion.id",
             "com.craft.Craft",
             "net.shinyfrog.bear":
            return .writing

        default:
            return .general
        }
    }

    private static func browserBias(from title: String) -> AppBias {
        let lower = title.lowercased()
        let codingKeywords = ["github", "gitlab", "stackoverflow", "cursor.sh",
                               "claude.ai", "chatgpt.com", "codex", "anthropic",
                               "linear.app", "jira", "vercel", "supabase"]
        let writingKeywords = ["notion", "docs.google", "medium", "substack",
                                "wordpress", "ghost", "bear", "obsidian"]
        if codingKeywords.contains(where: { lower.contains($0) }) { return .coding }
        if writingKeywords.contains(where: { lower.contains($0) }) { return .writing }
        return .browser
    }

    /// Returns a human-readable hint for the template
    static func contextHint(for context: CapturedContext) -> String {
        var parts: [String] = []
        if !context.appName.isEmpty { parts.append("App: \(context.appName)") }
        if !context.windowTitle.isEmpty { parts.append("Window: \(context.windowTitle)") }
        return parts.joined(separator: " | ")
    }
}
