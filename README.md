[![Stand With Ukraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/banner-direct-single.svg)](https://stand-with-ukraine.pp.ua)

# 🐈 AppCat

**A macOS switcher for links, files, apps, and windows.**

AppCat sits in your menu bar and decides where things open:

- Click a **link** → pick the browser, profile, or native app (or let a rule route it automatically).
- Open a **file** → pick from the apps that can actually handle it.
- Press **⌥Tab** → jump to any running app *or a specific open window* from a Cmd-Tab-style switcher.

Stop launching the wrong browser profile, stop dragging files onto Dock icons, and stop alt-tabbing through six windows to find the one you want.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
[![Made in Ukraine](https://img.shields.io/badge/made_in-ukraine-ffd700.svg?labelColor=0057b7)](https://stand-with-ukraine.pp.ua)

---

## 🚀 What AppCat does

### 🔗 Link routing
Set AppCat as your default browser and it intercepts every link:

- A floating picker appears near your cursor with your **browsers, browser profiles, and any native app** that handles the URL's host (e.g. a Figma link offers Figma.app).
- If a **URL rule** matches, the link is routed automatically — no picker.
- **Private/incognito:** hold `Option` or `Shift` while pressing a picker key to open the link in a private window.
- Multiple links at once open together in the target you choose.

### 🐈 App & window switcher (`⌥Tab`)
The reason AppCat earns its name. Press `⌥Tab` anywhere to open a HUD switcher showing:

- **Running apps and their individual open windows** as tiles — pick a specific window (e.g. the right VS Code project or Chrome window), not just the app.
- Apps **with open windows first**, background/menu-bar apps dimmed below a divider (both toggleable).
- Ordered by how often and how recently you actually use each app.
- Full keyboard control: arrows, `Tab`, positional keys, or just **type a name** to focus it, then `Return`.

Window awareness uses the Accessibility API (with a Window-menu fallback for Electron editors like VS Code, Cursor, and Zed), so it needs Accessibility permission.

`⌥⌘⇧B` re-opens the last picker.

### 📄 File open-with picker
AppCat registers as a handler for HTML, SVG, PDF and ~150 developer/config file types. Open one and it shows a **ranked picker of apps that can actually edit it** — view-only browsers are hidden for code/text files (you want to edit, not preview), and apps that can't meaningfully open anything are left out. You can override each app's file formats on the **Apps** screen.

### 🧭 URL rules & native-app routing
Auto-route links by pattern. Four match types:

| Type | Matches |
|------|---------|
| **Host** | exact host + subdomains (`github.com`) |
| **Host contains** | substring of the host (`atlassian`) |
| **URL contains** | substring of the whole URL, path included (`/client/`) |
| **Regex** | full regular expression |

Each rule targets a **browser + profile** or a **native app**. AppCat ships deep-link support for ~19 apps (Slack, Teams, Discord, Telegram, WhatsApp, Zoom, Figma, Notion, Miro, Linear, Jira, Obsidian, Loom, Spotify, 1Password, VS Code, …), converting web URLs to their app scheme where possible (e.g. `teams.microsoft.com` → `msteams:`).

### 📊 Main window
Beyond the pickers, AppCat has a full window (Dock icon appears while it's open):

- **Overview** — time saved, total opens, share auto-routed by rules, top browser, a 7-day chart.
- **History** — every open (up to 500), searchable; recent links are also in the menu bar.
- **Suggestions** — AppCat watches your habits and proposes rules ("you opened github.com in Arc 8× this week → make a rule?").

---

## ⌨️ Keyboard shortcuts

**Global:**

| Shortcut | Action |
|----------|--------|
| `⌥Tab` | Open the app/window switcher |
| `⌥⌘⇧B` | Re-open the last picker |
| Hold `⌥`, press `Tab` / `⇧Tab` | Optional hold-to-switch mode |
| `Caps Lock` or `Escape` taps | Optional service-key trigger |

Both are rebindable under **Settings → Shortcuts**.

**Inside any picker:**

| Key | Action |
|-----|--------|
| `Arrow keys` / `Tab` | Move focus (wraps around) |
| Type letters | Type-to-focus by app, browser, profile, or window name |
| `1`…`0` then `Q`…`M` | Jump to that position in toggle mode (or use a custom character you assign per item) |
| `Return` | Open the focused item |
| `Escape` | Dismiss |
| `Option` / `Shift` + key | *(link picker only)* open in private mode |

> Picker keys are plain characters — `⌘` and `⌃` are intentionally not used, so app-level shortcuts keep working.

---

## 🔍 Detection

**Browsers** (~24, detected live): Safari, Chrome (+ Canary/Testing), Firefox (+ Nightly/Dev), Arc, Edge, Brave, Opera, Vivaldi, Chromium, Orion, Zen, Waterfox, SigmaOS, GNOME Web, Tor Browser, Whale, Yandex, and more.

**Profiles:** Chromium profiles (from `Local State`) and Firefox profiles (from `profiles.ini`) appear as separate picker entries, each with its own optional hotkey and visibility.

**Apps:** every installed app is detected for the file picker and switcher; native-app routing covers the curated registry above.

---

## ⚡ Quick Start

### Install
1. Download the latest `.dmg` from [Releases](https://github.com/rmarinsky/AppCat/releases/latest).
2. Drag **AppCat** to Applications.
3. Launch it. Updates arrive automatically via Sparkle.

### First-time setup
1. **Set AppCat as your default browser** — Settings → General → Set as Default Browser.
2. **Grant Accessibility** (for the `⌥Tab` window switcher) when prompted, or in System Settings → Privacy & Security → Accessibility.
3. **Assign hotkeys (optional)** — the **Browsers** and **Apps** screens let you set a character per item; the **Shortcuts** tab holds the two global hotkeys.
4. **Add URL rules (optional)** — Settings → Rules.

---

## 🔒 Privacy

- **No accounts, no analytics, no telemetry, no tracking.** Your history, rules, and stats live only on your Mac in `~/Library/Application Support/AppCat/`.
- AppCat does make a few **functional** network requests: it fetches favicons (Google's S2 service), reads page titles, and follows link redirects to record where a link actually landed — plus Sparkle's update check. It is not fully offline, but nothing about you is sent anywhere.

---

## ⚙️ Settings

Menu bar icon → the main window has these tabs:

- **General** — default browser, launch at login, language.
- **Picker** — what the manual switcher includes (running-without-windows apps, background/menu-bar apps, picker exclusions, size).
- **Browsers** — visibility, order, per-browser & per-profile hotkeys.
- **Apps** — visibility, hotkeys, and per-app file-format editing.
- **Rules** — URL routing rules.
- **Shortcuts** — global hotkeys + the picker key reference.
- **About** — version, links, update check.

---

## 📦 Build from Source

### Requirements
- macOS 14.0+ (Sonoma)
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Steps
```bash
brew install xcodegen
git clone https://github.com/rmarinsky/AppCat.git
cd AppCat
./generate_project.sh        # generates AppCat.xcodeproj from project.yml
open AppCat.xcodeproj
```

Schemes:
- **AppCat** → Release build → `AppCat.app`
- **AppCat DEV** → Debug build with logging → `AppCat DEV.app` (separate bundle ID, safe to run alongside the release)

---

## ❓ FAQ

**Does AppCat collect any data?**
No accounts, analytics, or telemetry. History and settings stay on your Mac. It does fetch favicons/titles and check for updates — see [Privacy](#-privacy).

**Why does the `⌥Tab` switcher not show other apps' windows?**
It needs Accessibility permission. Grant it in System Settings → Privacy & Security → Accessibility, then reopen the switcher.

**Can I make it keyboard-first?**
Yes. Use Settings → Shortcuts for hold-to-switch or service-key activation, and assign per-browser/per-app picker hotkeys in Settings → Browsers or Settings → Apps.

**Does this work with Raycast/Alfred link handlers?**
Yes — anything that opens the system default browser goes through AppCat.

**How do I uninstall?**
Quit AppCat, drag it from Applications to Trash, and reset your default browser in System Settings.

---

## 🗺️ Roadmap

- [ ] **Hotkey-only mode** (skip the picker UI entirely)
- [ ] **Per-domain profile selection** (auto-pick a browser profile from the URL)
- [ ] **iCloud sync** for rules & settings across Macs
- [ ] **Open in an existing tab** when the target is already loaded

---

## 📄 License

[MIT License](LICENSE) — use it, fork it, whatever.

---

## 🙏 Acknowledgments

Built by [@rmarinsky](https://github.com/rmarinsky). Inspired by Choosy, Browserosaurus, and Velja — free, open-source, and actually maintained.

Sibling apps: **[Papuga](https://github.com/rmarinsky/papuga)** (keyboard-layout fixer) and Diduny.

---

## 💬 Feedback

- ⭐ Star the repo
- 🐛 [Report a bug](https://github.com/rmarinsky/AppCat/issues)
- 💡 Suggest a feature
- [Releases](https://github.com/rmarinsky/AppCat/releases)
