[![Stand With Ukraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/banner-direct-single.svg)](https://stand-with-ukraine.pp.ua)

# 🐈 AppCat

**macOS menu bar browser picker** — choose which browser, profile, or app opens every link with one click or hotkey.

Stop copy-pasting URLs between browsers. Stop launching the wrong profile. AppCat gives you instant control over where every link opens.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
[![Made in Ukraine](https://img.shields.io/badge/made_in-ukraine-ffd700.svg?labelColor=0057b7)](https://stand-with-ukraine.pp.ua)

---

## 🎯 Use Cases

### 1️⃣ Multiple Browser Profiles
**Problem:** You have Chrome Personal, Chrome Work, and constantly open links in the wrong profile.
**Solution:** AppCat shows all profiles in the picker. One click → right profile, every time.

```
Click a link → Picker appears → Choose "Chrome (Work)" → Done
```

### 2️⃣ Privacy-First Browsing
**Problem:** Opening banking links, medical results, or private searches requires manually launching incognito mode.
**Solution:** Hold `Option/Shift` or set a URL rule to auto-open in private mode.

```
Click banking URL → Auto-opens in Safari Private
Or: Option + Hotkey → Any browser in incognito
```

### 3️⃣ Native App Routing
**Problem:** Slack/Figma/Zoom links open in browser instead of the native app.
**Solution:** AppCat detects matching apps and prioritizes them in the picker.

```
slack.com/archives/... → Opens in Slack.app (not browser)
figma.com/file/... → Opens in Figma.app
zoom.us/j/... → Opens in Zoom.app
```

### 4️⃣ URL-Based Automation
**Problem:** GitHub links should always open in Arc, Jira in Chrome Work, YouTube in Safari.
**Solution:** Set URL rules by host, substring, or regex.

```
github.com/* → Arc Browser
*.atlassian.net/* → Chrome (Work Profile)
youtube.com/* → Safari
```

### 5️⃣ Testing Across Browsers
**Problem:** QA/Dev workflow requires checking the same URL in 5+ browsers.
**Solution:** Keyboard hotkeys let you open the same link instantly in any browser.

```
1. Copy URL
2. Press ⌘+1 → Opens in Chrome
3. Press ⌘+2 → Opens in Firefox
4. Press ⌘+3 → Opens in Safari
(All from the same clipboard URL)
```

### 6️⃣ Context-Aware Link Opening
**Problem:** Personal emails → Personal browser. Work docs → Work browser. Manual switching is tedious.
**Solution:** Set domain-based rules and profiles to auto-route.

```
mail.google.com → Chrome Personal
docs.google.com/a/company.com → Chrome Work
```

---

## ⚡ Quick Start

### Installation
1. Download the latest `.dmg` from [Releases](https://github.com/rmarinsky/AppCat/releases/latest)
2. Drag **AppCat** to Applications
3. Launch and set as default browser in Settings

Updates are delivered automatically via Sparkle once installed.

### First-Time Setup
1. **Set AppCat as default browser:**
   Settings → General → Default Browser → AppCat

2. **Configure hotkeys (optional):**
   AppCat → Settings → Apps → Assign keyboard shortcuts

3. **Add URL rules (optional):**
   Settings → Rules → Add rule for auto-routing specific domains

---

## 🚀 Features

### Browser Picker
- **Floating panel** near cursor with all installed browsers
- **Compact Cmd+Tab-style row** with icons and names
- **Keyboard navigation** (arrow keys, numbers, hidden type-to-focus + Return)
- **Instant dismiss** (Escape or click outside)

### Browser Detection
Auto-detects all installed browsers:
- **Chromium-based:** Chrome, Edge, Brave, Arc, Vivaldi, Opera, Zen, Chromium
- **WebKit-based:** Safari, Orion (Kagi)
- **Gecko-based:** Firefox, Waterfox, Tor Browser
- **Others:** SigmaOS, Whale, Yandex

### Profile Support
Pick specific browser profiles before opening:
- Chrome/Edge/Brave profiles
- Firefox profiles
- Arc spaces (if supported)

### Native App Routing
Links auto-open in matching native apps:
- **Communication:** Slack, Teams, Discord, Telegram, WhatsApp, Zoom
- **Productivity:** Figma, Notion, Miro, Linear, Jira, Obsidian
- **Dev Tools:** VS Code, GitHub Desktop
- **Media:** Spotify, YouTube Music
- **Security:** 1Password

### URL Rules
Auto-route links by pattern:
- **Host match:** `github.com` → Arc
- **Substring match:** `*atlassian.net*` → Chrome Work
- **Regex match:** `^https://meet\.google\.com/.*` → Chrome Personal

### Keyboard Shortcuts
| Action | Shortcut |
|--------|----------|
| Open with hotkey | Assign per-browser (e.g., `⌘+1` for Chrome) |
| Private mode | `Option/Shift + Hotkey` |
| Navigate picker | `Arrow Keys` |
| Confirm | `Return` |
| Cancel | `Escape` |

### Privacy & Performance
- **No tracking** — zero analytics, zero telemetry
- **No network calls** — fully offline
- **Lightweight** — lives in menu bar, no dock icon
- **Launch at login** — optional

---

## 🛠️ Configuration

### Settings Window
Access via menu bar icon → Settings:
- **General:** Default browser, launch at login
- **Apps:** Hotkey assignments, browser/app order
- **Rules:** URL routing patterns
- **Advanced:** Private mode defaults, picker position

### Example URL Rules
```
# Work-related domains → Chrome Work Profile
*.atlassian.net/* → Chrome (Work)
*.slack.com/client/* → Chrome (Work)

# Personal browsing → Safari Private
*banking.example.com* → Safari (Private)

# Development → Arc
github.com/* → Arc Browser
localhost:* → Arc Browser
```

---

## 📦 Build from Source

### Requirements
- macOS 14.0+ (Sonoma)
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Build Steps
```bash
# Install dependencies
brew install xcodegen

# Clone repository
git clone https://github.com/rmarinsky/AppCat.git
cd AppCat

# Generate Xcode project
xcodegen generate

# Open and build
open AppCat.xcodeproj
```

Build schemes:
- **AppCat** → Release build, produces AppCat.app
- **AppCat DEV** → Debug build with logging, produces AppCat DEV.app

---

## ❓ FAQ

**Q: Does AppCat collect any data?**
A: No. Zero analytics, zero telemetry, zero network calls. Fully offline.

**Q: Why does the picker appear in the wrong position?**
A: The picker tries to center near the cursor. If it's off-screen, it auto-adjusts. Check Settings → Advanced to tweak behavior.

**Q: Can I disable the picker and use only hotkeys?**
A: Not yet, but this is planned. For now, set hotkeys and press them immediately.

**Q: Does this work with Raycast/Alfred URL handlers?**
A: Yes, if they trigger the system default browser, AppCat will intercept.

**Q: How do I uninstall?**
A: Drag AppCat from Applications to Trash, then reset your default browser in System Settings.

---

## 🗺️ Roadmap

- [ ] **Hotkey-only mode** (skip picker UI)
- [ ] **Link history** (recent URLs with search)
- [ ] **Per-domain browser profiles** (auto-select profile based on URL)
- [ ] **iCloud sync** (rules & settings across Macs)
- [ ] **Browser tab detection** (open in existing tab if possible)
- [ ] **Custom app support** (add unlisted apps manually)

---

## 🐛 Known Issues

- Picker animation could be smoother (refactoring in progress)
- Some Electron apps don't pass URLs correctly (investigating)
- Browser profile detection may miss custom Firefox profiles

Report bugs via [GitHub Issues](https://github.com/rmarinsky/AppCat/issues).

---

## 📄 License

[MIT License](LICENSE) — use it, fork it, sell it, whatever.

---

## 🙏 Acknowledgments

Built by [@rmarinsky](https://github.com/rmarinsky) because copy-pasting URLs between browsers is annoying.

Inspired by tools like Choosy, Browserosaurus, and Velja — but free, open-source, and actually maintained.

---

## 💬 Feedback

If AppCat saves you 30+ context switches per day, consider:
- ⭐ Starring this repo
- 🐛 Reporting bugs
- 💡 Suggesting features
- 📢 Sharing with other multi-browser users

**Links:**
- [GitHub Issues](https://github.com/rmarinsky/AppCat/issues)
- [Releases](https://github.com/rmarinsky/AppCat/releases)
