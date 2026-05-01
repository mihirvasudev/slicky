import Foundation

/// All events emitted by the AgenticRewriter pipeline.
enum RewriteEvent {
    /// Intent classification completed
    case classified(intent: Intent)

    /// Tokens streaming from the draft phase
    case draftToken(String)

    /// Draft phase complete with full text
    case draftDone(String)

    /// Critique analysis result
    case critique(score: Int, issues: [String], shouldRefine: Bool)

    /// Tokens streaming from the refine phase
    case refineToken(String)

    /// Final rewrite text ready (either draft or refined)
    case final(String)

    /// Pipeline error
    case error(Error)
}

// MARK: - Intent

enum Intent: String, CaseIterable {
    case codingFeature = "coding-feature"
    case codingBug = "coding-bug"
    case codingRefactor = "coding-refactor"
    case writing = "writing"
    case research = "research"
    case general = "general"

    var displayName: String {
        switch self {
        case .codingFeature:  return "Feature"
        case .codingBug:      return "Bug Fix"
        case .codingRefactor: return "Refactor"
        case .writing:        return "Writing"
        case .research:       return "Research"
        case .general:        return "General"
        }
    }

    var emoji: String {
        switch self {
        case .codingFeature:  return "✨"
        case .codingBug:      return "🐛"
        case .codingRefactor: return "🔧"
        case .writing:        return "✍️"
        case .research:       return "🔍"
        case .general:        return "💬"
        }
    }

    var templateName: String { rawValue }
}
