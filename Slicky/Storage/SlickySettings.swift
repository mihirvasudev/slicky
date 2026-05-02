import AppKit
import Combine

final class SlickySettings: ObservableObject {
    static let defaultHotkeyKey: HotKeyCode = .k
    static let defaultHotkeyModifiers: NSEvent.ModifierFlags = [.command, .option]

    // MARK: - Models

    enum DraftModel: String, CaseIterable, Identifiable {
        // Real Anthropic API model IDs (verified May 2026).
        // The previous build shipped with `claude-sonnet-4-5` / `claude-opus-4-5`
        // which never existed and caused empty-stream errors.
        case sonnet = "claude-sonnet-4-6"
        case haiku  = "claude-haiku-4-5"
        case opus   = "claude-opus-4-7"

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .sonnet: return "Claude Sonnet 4.6 (balanced)"
            case .haiku:  return "Claude Haiku 4.5 (fast)"
            case .opus:   return "Claude Opus 4.7 (best quality)"
            }
        }
    }

    // MARK: - Capture strategy

    /// Order of attempts Slicky uses to read what you want rewritten.
    /// `smart` is the rock-solid default: read the AX selection if the app
    /// supports it, otherwise read whatever the user already put on the
    /// clipboard. `auto` adds a last-ditch synthetic Cmd+C, which is
    /// brittle inside Electron apps like Cursor.
    enum CaptureStrategy: String, CaseIterable, Identifiable {
        case smart       // AX → existing clipboard. No synthesized copy. (default)
        case auto        // AX → existing clipboard → synthetic Cmd+C.
        case clipboardOnly // Always use existing clipboard, skip AX.

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .smart:         return "Smart (recommended)"
            case .auto:          return "Smart + auto-copy fallback"
            case .clipboardOnly: return "Clipboard only"
            }
        }
        var explanation: String {
            switch self {
            case .smart:
                return "Reads selected text natively when possible. In Electron apps (Cursor, VS Code, Discord, Slack), copy first (⌘C), then press the hotkey."
            case .auto:
                return "Same as Smart, but Slicky also tries to press ⌘C for you as a last resort. Less reliable in Cursor — keep the hotkey held briefly so the modifiers can't leak into the synthetic copy."
            case .clipboardOnly:
                return "Always uses whatever's on your clipboard. Pure Clippy mode: copy first (⌘C), press hotkey. Works identically in every app."
            }
        }
    }

    // MARK: - Published

    @Published var draftModel: DraftModel = .sonnet
    @Published var classifyModel: DraftModel = .haiku
    @Published var skipCritique: Bool = false
    @Published var captureStrategy: CaptureStrategy = .smart {
        didSet { defaults.set(captureStrategy.rawValue, forKey: "captureStrategy") }
    }
    @Published var onboardingComplete: Bool = false {
        didSet { defaults.set(onboardingComplete, forKey: "onboardingComplete") }
    }
    @Published private(set) var hotkeyDisplayString: String = ""

    // These are persisted separately because UserDefaults can't store enums easily
    private let defaults = UserDefaults.standard

    // Hotkey stored as separate key + modifier raw values
    var hotkeyKey: HotKeyCode {
        get {
            let stored = UInt32(defaults.integer(forKey: "hotkeyKeyCode"))
            return HotKeyCode(rawValue: stored) ?? Self.defaultHotkeyKey
        }
        set {
            defaults.set(Int(newValue.rawValue), forKey: "hotkeyKeyCode")
            refreshHotkeyDisplay()
        }
    }

    var hotkeyModifiers: NSEvent.ModifierFlags {
        get {
            let raw = defaults.integer(forKey: "hotkeyModifiers")
            return raw == 0 ? Self.defaultHotkeyModifiers : NSEvent.ModifierFlags(rawValue: UInt(raw))
        }
        set {
            defaults.set(Int(newValue.rawValue), forKey: "hotkeyModifiers")
            refreshHotkeyDisplay()
        }
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
        if let raw = defaults.string(forKey: "captureStrategy"),
           let strategy = CaptureStrategy(rawValue: raw) {
            captureStrategy = strategy
        }
        onboardingComplete = defaults.bool(forKey: "onboardingComplete")
        refreshHotkeyDisplay()
    }

    func persist() {
        defaults.set(draftModel.rawValue, forKey: "draftModel")
        defaults.set(classifyModel.rawValue, forKey: "classifyModel")
        defaults.set(skipCritique, forKey: "skipCritique")
        defaults.set(captureStrategy.rawValue, forKey: "captureStrategy")
        defaults.set(onboardingComplete, forKey: "onboardingComplete")
    }

    func setHotkey(key: HotKeyCode, modifiers: NSEvent.ModifierFlags) {
        defaults.set(Int(key.rawValue), forKey: "hotkeyKeyCode")
        defaults.set(Int(modifiers.rawValue), forKey: "hotkeyModifiers")
        refreshHotkeyDisplay()
    }

    func resetHotkey() {
        setHotkey(key: Self.defaultHotkeyKey, modifiers: Self.defaultHotkeyModifiers)
    }

    func refreshHotkeyDisplay() {
        hotkeyDisplayString = Self.formatHotkey(key: hotkeyKey, modifiers: hotkeyModifiers)
    }

    static func formatHotkey(key: HotKeyCode, modifiers: NSEvent.ModifierFlags) -> String {
        "\(formatModifiers(modifiers))\(key.displayString)"
    }

    static func formatModifiers(_ modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        return parts.joined()
    }
}

// MARK: - Hotkey Key Codes (Carbon key codes for common keys)

enum HotKeyCode: UInt32 {
    case a = 0
    case s = 1
    case d = 2
    case f = 3
    case h = 4
    case g = 5
    case z = 6
    case x = 7
    case c = 8
    case v = 9
    case b = 11
    case q = 12
    case w = 13
    case e = 14
    case r = 15
    case y = 16
    case t = 17
    case one = 18
    case two = 19
    case three = 20
    case four = 21
    case six = 22
    case five = 23
    case equal = 24
    case nine = 25
    case seven = 26
    case minus = 27
    case eight = 28
    case zero = 29
    case rightBracket = 30
    case o = 31
    case u = 32
    case leftBracket = 33
    case i = 34
    case p = 35
    case returnKey = 36
    case l = 37
    case j = 38
    case quote = 39
    case k = 40
    case semicolon = 41
    case backslash = 42
    case comma = 43
    case slash = 44
    case n = 45
    case m = 46
    case period = 47
    case tab = 48
    case space = 49
    case grave = 50

    var displayString: String {
        switch self {
        case .a: return "A"
        case .s: return "S"
        case .d: return "D"
        case .f: return "F"
        case .h: return "H"
        case .g: return "G"
        case .z: return "Z"
        case .x: return "X"
        case .c: return "C"
        case .v: return "V"
        case .b: return "B"
        case .q: return "Q"
        case .w: return "W"
        case .e: return "E"
        case .r: return "R"
        case .y: return "Y"
        case .t: return "T"
        case .one: return "1"
        case .two: return "2"
        case .three: return "3"
        case .four: return "4"
        case .five: return "5"
        case .six: return "6"
        case .seven: return "7"
        case .eight: return "8"
        case .nine: return "9"
        case .zero: return "0"
        case .equal: return "="
        case .minus: return "-"
        case .leftBracket: return "["
        case .rightBracket: return "]"
        case .o: return "O"
        case .u: return "U"
        case .i: return "I"
        case .p: return "P"
        case .returnKey: return "↩"
        case .l: return "L"
        case .j: return "J"
        case .quote: return "\""
        case .k: return "K"
        case .semicolon: return ";"
        case .backslash: return "\\"
        case .comma: return ","
        case .slash: return "/"
        case .n: return "N"
        case .m: return "M"
        case .period: return "."
        case .tab: return "⇥"
        case .space: return "Space"
        case .grave: return "`"
        }
    }
}
