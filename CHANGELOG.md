# Changelog

## [1.0.0] — Unreleased

### Added
- Global hotkey (⌘⌥K by default) to trigger rewrite from anywhere on macOS
- **Clippy-style capture**: read what you already copied, no synthetic Cmd+C needed in Electron apps
- Capture strategy setting: Smart (default) / Smart + auto-copy fallback / Clipboard only
- "Test Capture" diagnostic in Settings — shows AX selection, current clipboard, age, and which path would be chosen
- HUD badge shows where text came from ("from selection", "from clipboard", "auto-copied")
- Capture-source-aware error messages: tells the user *exactly* what to do next per app type
- Onboarding "How Slicky reads your text" step explaining native vs Electron capture paths
- AX-based selected text capture for native apps (TextEdit, Notes, Safari, Mail)
- Agentic pipeline: Classify → Draft → Critique → Refine
- Six intent-specific prompt templates: coding-feature, coding-bug, coding-refactor, writing, research, general
- App context bias (IDE/terminal → coding bias, writing tools → writing bias)
- Streaming HUD panel with live token display and pipeline timeline
- AX-based text injection with clipboard+Cmd+V fallback
- Keychain-stored Anthropic API key
- Settings: model picker, skip-critique toggle, hotkey rebinding
- Onboarding wizard with Accessibility permission flow
- Menu bar status item with wand icon

### Changed
- **Default behaviour rewritten for reliability**: Slicky no longer synthesises Cmd+C by default. In apps where AX exposes the selection (native apps), it reads the selection. Otherwise it reads what you put on the clipboard. The synthetic-copy code path is now opt-in under "Smart + auto-copy fallback".
- Menu bar error popovers now stay visible 8s (was 5s) so long error messages can be read.
