# Slicky

**Turn any sloppy prompt into a great one — anywhere on macOS.**

Press **⌘⌥K** → watch an agentic AI pipeline transform your prompt into a structured, high-leverage version with goals, phases, tests, and acceptance criteria — then paste it back.

Works in Cursor, Claude Code in Terminal, Codex CLI, claude.ai, ChatGPT, Slack, Notion, and anywhere you can select or copy text.

## How it works

Slicky has two capture paths and picks the right one automatically:

| Where you are | What you do |
|---|---|
| **Native apps** (TextEdit, Notes, Safari, Mail, native input fields) | Select → press ⌘⌥K. Slicky reads the selection through Accessibility. |
| **Electron apps** (Cursor, VS Code, Slack, Discord, Notion) | Copy first (⌘C), then press ⌘⌥K. Slicky reads what you put on the clipboard. |

Then watch the pipeline stream live:
- **Classify** — detects intent (coding feature, bug fix, writing, research…)
- **Draft** — applies a template tuned to your intent, streams the rewrite
- **Critique** — scores the draft against a rubric, identifies gaps
- **Refine** — fixes the issues, produces the final version

**Press Return** to paste it back, **Tab** to edit first, **Esc** to cancel.

## Setup

1. Download and open `Slicky.dmg`
2. Move Slicky to `/Applications`
3. Open Slicky — it lives in your menu bar (wand icon ✦)
4. Complete the onboarding: paste your [Anthropic API key](https://console.anthropic.com/settings/keys) and grant Accessibility permission
5. Select any prompt text and press ⌘⌥K

## Settings

- **⌘,** or menu bar → Settings
- **Text capture strategy**: Smart (default) / Smart + auto-copy fallback / Clipboard only
- **Test Capture**: verify what Slicky sees in any app — shows AX selection, current clipboard, and which one would be used
- Switch models (Sonnet for quality, Haiku for speed)
- Toggle "Skip critique" for a faster 1-step rewrite
- Rebind the global hotkey if it conflicts with another app
- View Accessibility permission status

### Capture strategies

- **Smart** (default): reads the live AX selection when the app supports it; otherwise reads what you already copied. No synthetic events. Works everywhere if you press ⌘C in Electron apps first.
- **Smart + auto-copy fallback**: same as Smart, but if both fail Slicky tries to press ⌘C for you. Less reliable in Cursor — useful in apps that don't expose AX but where you forgot to copy.
- **Clipboard only**: pure Clippy mode. Always uses whatever's on the clipboard. Predictable in every app.

## Templates

Six intent-specific rewrite templates live in `Slicky.app/Contents/Resources/Templates/`:

| Template | Triggered when |
|----------|---------------|
| `coding-feature.md` | Building new functionality |
| `coding-bug.md` | Bug reports and debugging |
| `coding-refactor.md` | Cleanup, migration, restructuring |
| `writing.md` | Blog posts, emails, docs |
| `research.md` | Questions, explanations, comparisons |
| `general.md` | Everything else |

## Privacy

- Your API key is stored exclusively in macOS Keychain
- No data is sent to any server except Anthropic's API
- No analytics, no telemetry, no account required

## Building

**You don't need Xcode locally.** GitHub Actions builds and notarizes for you.

```bash
# Get an unsigned build right now (no secrets needed):
# Push to GitHub → Actions → Build Slicky → Run workflow → download artifact
# Then:
xattr -cr Slicky.app && open Slicky.app
```

For signed `.dmg` releases see [BUILDING.md](BUILDING.md).

If you do have Xcode locally:
```bash
git clone https://github.com/mihir/slicky
cd slicky
xcodegen generate
open Slicky.xcodeproj
```

## Hotkeys

The default is **⌘⌥K**, chosen to avoid Cursor's **⌘⇧K** "Delete Line" shortcut and common Slack shortcuts. You can rebind it in Settings.
