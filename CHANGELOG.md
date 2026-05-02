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
- **Capture cascade rebuilt**: AX selection → fresh clipboard (≤60s) → AX Edit→Copy menu action → synthetic Cmd+C → fail. Stale clipboard text is never silently used; if synthetic capture fails, you get a clear "press ⌘C and try again" message naming the clipboard's age.
- **AX-driven Edit→Copy** is now the first auto-capture mechanism — it dispatches Cursor's actual menu command via Accessibility instead of synthesising a keyboard event, which is dramatically more reliable in Electron apps.
- HUD now shows the original prompt **expanded by default** when captured from clipboard or auto-copy, with a "verify ↓ — Esc to cancel if this is wrong" hint so wrong-text captures are caught in the first second instead of after the model has already run.
- Menu bar error popovers now stay visible 8s (was 5s) so long error messages can be read.

### Fixed
- **Wrong model IDs**: shipped with `claude-sonnet-4-5` and `claude-opus-4-5`, neither of which exist. Updated to real Anthropic model IDs (`claude-sonnet-4-6`, `claude-haiku-4-5`, `claude-opus-4-7`). Old persisted settings auto-migrate to the new defaults.
- **Empty-rewrite bug**: SSE parser was defaulting unknown event types to `content_block_delta`, silently swallowing `error` events and `stop_reason` payloads. The rewriter now surfaces real Anthropic errors (overloaded, content_filtered, refused) instead of producing a blank prompt with a "Score 1/10, draft is empty" critique.
- **Empty draft detection**: when the model returns zero tokens (e.g. shell-script content the model declined to rewrite), the HUD shows a clear actionable error instead of running critique-on-nothing.
- **Stale clipboard hijacking**: previously, if you pressed the hotkey in Cursor without copying first, Slicky silently rewrote whatever was last on your clipboard from minutes earlier. It now fails fast with a message naming the stale clipboard's age.
- API errors now NSLog to Console.app for debugging.

### Added (this build)
- **Test API Key + Model** button in Settings: sends a 1-token probe to Anthropic and reports success/401/404/error inline. No more guessing whether the key, the model ID, or the network is the problem.
