# alfred-windows-app
Simple Alfred workflow to search and open saved bookmarks from [Windows App](https://apps.apple.com/us/app/windows-app/id1295203466) — Microsoft's macOS remote desktop client, formerly named *Microsoft Remote Desktop*. Based on https://github.com/ctwise/alfred-workflows/tree/master/remote-desktop

**Requires [Alfred](https://www.alfredapp.com/) with the Powerpack, and Windows App installed in `/Applications`.**

<p align="center">
  <img src="screenshot.png" width="493" alt="Alfred showing the rdp keyword listing saved Windows App bookmarks, each row with the desktop name and an Open desktop subtitle">
</p>

## Usage
Trigger Alfred and use the `rdp` keyword:
- `rdp ` — list every saved bookmark.
- `rdp <name>` — filter bookmarks whose name contains `<name>`.
- `rdp <user@host[:port]>` — connect directly to an ad-hoc host (IP or FQDN) that isn't saved as a bookmark. A **Connect to …** item appears alongside any matching bookmarks. The username and port are optional: `rdp 192.168.4.3`, `rdp me@192.168.4.3`, and `rdp me@host.example.com:3390` all work. With no username, Windows App prompts for credentials.

Select a result and press Enter to open the session in Windows App.

## Why?
The version in the source repository was no longer maintained and no longer functional. It also relied on `osascript` to bring Microsoft Remote Desktop to the foreground and simulate keypresses to open a session, which did not always work reliably. This workflow instead drives Windows App through its [command line interface](https://learn.microsoft.com/en-us/windows-app/cli-macos), which exposes the same `--script bookmark` commands the old app used.

## How?
Everything lives in [`windows_app.rb`](windows_app.rb), which Alfred invokes with a subcommand:
- `windows_app.rb list "{query}"` (the Script Filter): runs `--script bookmark list` to get the saved bookmarks as CSV, filters by query, and returns matches to Alfred as Script Filter JSON, letting you search through your bookmarks. An empty query returns every bookmark, so the keyword alone lists them all. When the query parses as `[user@]host[:port]`, it also appends a **Connect to …** item whose arg is an `adhoc:<target>` token (not a URI — see below).
- `windows_app.rb open "{query}"` (the Action): if the arg is an `adhoc:<target>` token, it builds the `rdp://` URI from `<target>` and `open`s it directly; otherwise it treats the arg as a bookmark ID, runs `--script bookmark export <id> --uri`, and `open`s that. Either way Windows App launches the session.

The file is organized into a few units:
- `RemoteTarget` parses an ad-hoc `[user@]host[:port]` target and builds the `rdp://` URI. Windows App rejects a minimal `full address`+`username` URI with *"The URL is not valid"*, so it emits the app's full default attribute set (captured from `--script bookmark export`) with `full address`, the optional port, and `username` substituted in.
- `WindowsApp` wraps the binary (`bookmarks`, `export_uri`) and the OS `open` (`open_uri`). It locates the binary with `WINDOWS_APP` → the standard `/Applications` path → a Spotlight (`mdfind`) lookup by bundle id `com.microsoft.rdc.macos` → the standard path as a fallback; the fast common case avoids any subprocess since the Script Filter runs per keystroke. Opening uses `open -b com.microsoft.rdc.macos` so the session lands in Windows App even if another app is registered for the `rdp://` scheme.
- `Workflow` is the two commands (`list`/`open`) built on those.
- `Feedback` builds the Script Filter JSON.

The ad-hoc item passes the bare target (not a pre-built URI) through Alfred so the URI's `&`/`%` characters — which Alfred mangles in argument substitution — are only ever produced inside Ruby, just like the bookmark path.

## Testing
Run the unit tests on the system Ruby:

```sh
ruby test/windows_app_test.rb
```

Lint with [RuboCop](https://rubocop.org/) (config in [`.rubocop.yml`](.rubocop.yml)). The system Ruby (2.6) is too old for current RuboCop, so run it through a newer Ruby — e.g. via Nix:

```sh
nix-shell -p rubocop --run rubocop
```

## Installation
Download the latest [`Windows-App.alfredworkflow`](https://github.com/thanegill/alfred-windows-app/releases/latest) and double-click it to import into Alfred. It runs on the system Ruby that ships with macOS, so there's nothing to build.

## Demo data
`windows_app.rb` reads the Windows App binary path from the `WINDOWS_APP` environment variable, defaulting to `/Applications/Windows App.app/Contents/MacOS/Windows App`. Point it at any executable that speaks the same `--script bookmark` interface.

[`test/fake-windows-app`](test/fake-windows-app) is such a stand-in: it returns a fixed set of fake bookmarks, so you can demo or screenshot the workflow without exposing your real desktops. To use it, set `WINDOWS_APP` to its absolute path — either inline:

```sh
WINDOWS_APP="$PWD/test/fake-windows-app" ruby windows_app.rb list prod
```

or, to drive Alfred itself, add it under the workflow's **Configuration → Workflow Environment Variables** in Alfred, then remove it when you're done.
