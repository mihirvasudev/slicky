import AppKit
import Combine

final class SlickySettings: ObservableObject {
    // MARK: - Models

    enum DraftModel: String, CaseIterable, Identifiable {
        case sonnet = "claude-sonnet-4-5"
        case haiku = "claude-haiku-4-5"
        case opus = "claude-opus-4-5"

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .sonnet: return "Claude Sonnet (balanced)"
            case .haiku: return "Claude Haiku (fast)"
            case .opus: return "Claude Opus (best quality)"
            }
        }
    }

    // MARK: - Published

    @Published var draftModel: DraftModel = .sonnet
    @Published var classifyModel: DraftModel = .haiku
    @Published var skipCritique: Bool = false
    @Published var onboardingComplete: Bool = false {
        didSet { defaults.set(onboardingComplete, forKey: "onboardingComplete") }
    }
    @Published var hotkeyDisplayString: String = "⌘⌥K"

    // These are persisted separately because UserDefaults can't store enums easily
    private let defaults = UserDefaults.standard

    // Hotkey stored as separate key + modifier raw values
    var hotkeyKey: HotKeyCode {
        get { HotKeyCode(rawValue: UInt32(defaults.integer(forKey: "hotkeyKeyCode"))) ?? .k }
        set { defaults.set(Int(newValue.rawValue), forKey: "hotkeyKeyCode") }
    }

    var hotkeyModifiers: NSEvent.ModifierFlags {
        get {
            let raw = defaults.integer(forKey: "hotkeyModifiers")
            return raw == 0 ? [.command, .option] : NSEvent.ModifierFlags(rawValue: UInt(raw))
        }
        set { defaults.set(Int(newValue.rawValue), forKey: "hotkeyModifiers") }
    }

    init() {
        // Load persisted values
        if let modelRaw = defaults.string(forKey: "draftModel"),
           let model = DraftModel(rawValue: modelRaw) {
            draftModel = model
        }
        if let raw = defaults.string(forKey: "classifyModel"),
           let model = DraftModel(rawValue: raw) {
            classifyModel = model
        }
        skipCritique = defaults.bool(forKey: "skipCritique")
        onboardingComplete = defaults.bool(forKey: "onboardingComplete")
    }

    func persist() {
        defaults.set(draftModel.rawValue, forKey: "draftModel")
        defaults.set(classifyModel.rawValue, forKey: "classifyModel")
        defaults.set(skipCritique, forKey: "skipCritique")
        defaults.set(onboardingComplete, forKey: "onboardingComplete")
    }
}

// MARK: - Hotkey Key Codes (Carbon key codes for common keys)

enum HotKeyCode: UInt32 {
    case k = 40
    case l = 37
    case p = 35
    case space = 49

    var displayString: String {
        switch self {
        case .k: return "K"
        case .l: return "L"
        case .p: return "P"
        case .space: return "Space"
        }
    }
}
