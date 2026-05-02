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
        Key(carbonKeyCode: code.rawValue) ?? .k
    }

}
