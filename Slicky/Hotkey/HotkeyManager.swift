import HotKey
import AppKit

final class HotkeyManager {
    private var hotKey: HotKey?

    func register(key: HotKeyCode, modifiers: NSEvent.ModifierFlags, handler: @escaping () -> Void) {
        hotKey = HotKey(key: mapKey(key), modifiers: modifiers)
        hotKey?.keyDownHandler = handler
    }

    func unregister() {
        hotKey = nil
    }

    // MARK: - Mapping

    private func mapKey(_ code: HotKeyCode) -> Key {
        switch code {
        case .k: return .k
        case .l: return .l
        case .p: return .p
        case .space: return .space
        }
    }

}
