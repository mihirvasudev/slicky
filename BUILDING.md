# Building Slicky

You don't need Xcode on your local machine. GitHub Actions builds, signs, and notarizes everything for you.

## Quick start — get an unsigned build right now

1. Push this repo to GitHub (public or private, doesn't matter)
2. Go to **Actions → Build Slicky → Run workflow**
3. Wait ~5 minutes
4. Download `Slicky-unsigned.zip` from the Artifacts section
5. On your Mac (macOS 12):
   ```bash
   unzip Slicky-unsigned.zip
   xattr -cr Slicky.app    # remove quarantine so macOS lets it run
   open Slicky.app
   ```

That's it. The unsigned build works for personal use on your own machine.

---

## Setting up signed + notarized releases (one-time setup)

For a proper `.dmg` you can share with others, you need four GitHub secrets. This takes about 15 minutes to set up.

### 1. Export your Developer ID certificate

You need a **Developer ID Application** certificate. If you don't have one yet:
- Go to [developer.apple.com/account](https://developer.apple.com/account) → Certificates → + → "Developer ID Application"
- Download and double-click to add it to Keychain

Then export it:
1. Open **Keychain Access**
2. Find "Developer ID Application: Your Name (TEAMID)" under My Certificates
3. Right-click → **Export** → save as `certificate.p12`
4. Set a strong password — you'll need this for the `DEVELOPER_ID_P12_PASSWORD` secret

Convert to base64:
```bash
base64 -i certificate.p12 | pbcopy
```
This copies the base64 string to your clipboard.

### 2. Get an App-Specific Password for notarization

1. Go to [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords
2. Generate a new password, label it "Slicky Notarization"
3. Copy it — you'll use this for `NOTARIZATION_PASSWORD`

### 3. Find your Team ID

Go to [developer.apple.com/account](https://developer.apple.com/account) → Membership → Team ID (a 10-character code like `ABC123DEF4`).

### 4. Add secrets to GitHub

Go to your repo → **Settings → Secrets and variables → Actions → New repository secret**. Add these five:

| Secret name | Value |
|---|---|
| `DEVELOPER_ID_P12` | The base64 string from step 1 |
| `DEVELOPER_ID_P12_PASSWORD` | The password you set when exporting |
| `APPLE_TEAM_ID` | Your Team ID (e.g. `ABC123DEF4`) |
| `NOTARIZATION_APPLE_ID` | Your Apple ID email |
| `NOTARIZATION_PASSWORD` | The app-specific password from step 2 |
| `KEYCHAIN_PASSWORD` | Any random string (e.g. `slicky-build-2024`) |

### 5. Create a release

```bash
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions will:
1. Build the app with your Developer ID certificate
2. Notarize it with Apple
3. Staple the ticket
4. Create a `.dmg` and attach it to the GitHub Release

---

## Workflow overview

```
Push to main ──→ Build (unsigned) ──→ Upload artifact
                                       (download + xattr -cr to run)

Push tag v* ───→ Build (signed) ──→ Notarize ──→ GitHub Release with .dmg
```

The unsigned build runs in ~4 minutes. The signed+notarized release takes ~8–12 minutes (notarization adds a few minutes).

---

## Updating templates without a full rebuild

The prompt templates are in `Slicky/Resources/Templates/*.md`. You can edit them and commit — the next build picks them up automatically. No Swift code changes needed.

## Changing models

Edit `Slicky/Storage/SlickySettings.swift` — the `DraftModel` enum lists available Claude models. Add new model IDs there.
