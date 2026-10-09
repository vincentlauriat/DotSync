# DotSync

Menu bar app for the `~/.dotfiles` sync (repo `vincentlauriat/dotfiles`).

| Feature | |
|---|---|
| Icon state: OK / syncing / needs attention / broken | ✅ |
| Last sync (time, result: ok, conflict, secret blocked, network) | ✅ |
| Pending local changes, commits to push / pull, links to repair | ✅ |
| "Synchroniser" button (⌘S) — runs `~/.dotfiles/dot sync` | ✅ |
| Toggle the 30-min launchd autosync | ✅ |
| Launch at login (SMAppService) | ✅ |
| Open log / repo folder / GitHub | ✅ |
| Automatic updates (Sparkle, daily check) | ✅ |

DotSync holds no logic: it runs `dot status --json` every 60 s and when the menu opens.
`dot sync` takes a lock, so the button and launchd never run concurrently. The result
goes to `~/.config/dotfiles/last-sync.json`.

## Install

Download the DMG from [Releases](https://github.com/vincentlauriat/DotSync/releases) (signed and notarized), drag it into Applications. Later versions arrive through Sparkle.

## Build

```bash
xcodegen generate
xcodebuild -scheme DotSync -configuration Release -derivedDataPath build/dd build
ditto build/dd/Build/Products/Release/DotSync.app /Applications/DotSync.app
```

Requires macOS 14+ and `~/.dotfiles` cloned (see the dotfiles README).

## Project layout

```
DotSync/
├── DotSyncApp.swift   # @main, MenuBarExtra
├── DotService.swift   # runs dot (Process), polling, state
├── DotStatus.swift    # Codable mirror of `dot status --json` + health
└── MenuView.swift     # menu UI
Scripts/release.sh     # build → sign → DMG → notarize → staple → Sparkle appcast
project.yml            # XcodeGen
```
