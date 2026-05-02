import AppKit
import ApplicationServices

/// Performs Edit → Copy via the target app's Accessibility tree instead of
/// synthesizing a Cmd+C keyboard event. This is dramatically more reliable
/// in Electron apps (Cursor, VS Code, Slack) because the menu action is
/// dispatched through the app's normal command machinery — no event taps,
/// no focus dancing, no modifier-leak issues.
///
/// Returns `true` if the menu item was successfully pressed.
enum AXMenuCopy {
    static func performCopy(in app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        // Walk: app → menu bar → Edit → (submenu) → Copy
        guard let menuBar = copyChild(of: axApp, attribute: kAXMenuBarAttribute) else {
            NSLog("Slicky AX menu copy: no menu bar for %@", app.localizedName ?? "<unknown>")
            return false
        }

        // Most localized menu titles for "Edit"; we try each.
        // For now we use English — most Electron app users have English menus.
        for editTitle in ["Edit", "edit"] {
            guard let editMenu = findChild(in: menuBar, role: kAXMenuBarItemRole, title: editTitle) else { continue }
            // The menu bar item contains a child of role AXMenu, which contains AXMenuItems.
            guard let editSubmenu = firstChild(of: editMenu, role: kAXMenuRole) else { continue }
            for copyTitle in ["Copy", "copy"] {
                if let copyItem = findChild(in: editSubmenu, role: kAXMenuItemRole, title: copyTitle) {
                    let result = AXUIElementPerformAction(copyItem, kAXPressAction as CFString)
                    if result == .success {
                        return true
                    }
                    NSLog("Slicky AX menu copy: PressAction returned %d", result.rawValue)
                }
            }
        }
        return false
    }

    // MARK: - AX helpers

    private static func copyChild(of element: AXUIElement, attribute: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref).rawValue == 0,
              let value = ref, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref).rawValue == 0,
              let value = ref else { return [] }
        // The CFArray contains AXUIElement values; bridge through NSArray.
        guard let array = value as? NSArray else { return [] }
        return array.compactMap { item in
            guard CFGetTypeID(item as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
            return unsafeBitCast(item as CFTypeRef, to: AXUIElement.self)
        }
    }

    private static func firstChild(of element: AXUIElement, role: String) -> AXUIElement? {
        children(of: element).first { childRole(of: $0) == role }
    }

    private static func findChild(in element: AXUIElement, role: String, title: String) -> AXUIElement? {
        children(of: element).first { child in
            childRole(of: child) == role && childTitle(of: child) == title
        }
    }

    private static func childRole(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &ref).rawValue == 0 else {
            return nil
        }
        return ref as? String
    }

    private static func childTitle(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &ref).rawValue == 0 else {
            return nil
        }
        return ref as? String
    }
}
