# Claude Usage Bar

A tiny native macOS menu bar app that always shows your Claude plan usage:

```
10%  43%
 5h   7d
```

- **5h**: current 5-hour session window
- **7d**: weekly window
- **5h** colors: green < 50%, orange ≥ 50%, red ≥ 80%
- **7d** colors: the week is split into 7 daily portions of ~14.3%. On day *n* of the window the budget is *n* × 14.3%. Orange once usage reaches 85% of that budget, red at 90% of the whole week, green otherwise.
- **Hover** shows when each window resets. **Click** opens a menu with reset times, how much of each window has elapsed (to compare against your usage), the last update time, *Refresh* and *Quit*.

It reads the OAuth token that Claude Code stores in the macOS login keychain (`Claude Code-credentials`) and calls the same usage endpoint Claude Code uses for `/usage`. It refreshes every 60 s and again on wake from sleep. It never refreshes or writes the token itself: if the token has expired, the numbers turn grey with a ⚠︎ until Claude Code renews it.

## Requirements

- macOS 13+ (Apple Silicon)
- Xcode Command Line Tools (`swiftc`)
- Claude Code logged in with a Claude subscription (Pro/Max)

## Build & run

```sh
./build.sh
open build/ClaudeUsageBar.app
```

To install it in `~/Applications` and start it at login (LaunchAgent):

```sh
./install.sh      # remove with ./uninstall.sh
```

Thresholds and the poll interval are constants at the top of `Sources/main.swift`.

> The usage endpoint is undocumented and may change.
