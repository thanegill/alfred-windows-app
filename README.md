# alfred-rdp-workflow
Simple Alfred workflow to search and open saved bookmarks from [Windows App](https://apps.apple.com/us/app/windows-app/id1295203466) — Microsoft's macOS remote desktop client, formerly named *Microsoft Remote Desktop*. Based on https://github.com/ctwise/alfred-workflows/tree/master/remote-desktop

**Requires [Alfred](https://www.alfredapp.com/) with the Powerpack, and Windows App installed in `/Applications`.**

# Why?
The version in the source repository was no longer maintained and no longer functional. It also relied on `osascript` to bring Microsoft Remote Desktop to the foreground and simulate keypresses to open a session, which did not always work reliably. This workflow instead drives Windows App through its [command line interface](https://learn.microsoft.com/en-us/windows-app/cli-macos), which exposes the same `--script bookmark` commands the old app used.

# How?
Two parts:
- [`list_desktops.rb`](list_desktops.rb): Accepts one argument, the search query, and runs `--script bookmark list` to get the saved bookmarks as CSV. It filters by query and returns matches to Alfred via [`alfred_feedback.rb`](alfred_feedback.rb), letting you search through your bookmarks.

![rdp alfred search](https://imgur.com/ubdLdBw.gif)

- [`open_desktop.rb`](open_desktop.rb): Accepts one argument, the ID of the selected bookmark, and runs `--script bookmark export <id> --uri` to get the `rdp://` URI. It then `open`s the URI and Windows App launches the session.

# Todo:

- Add testing/linting

# Installation
You can compile it from source or download the latest binary from the releases page.

https://github.com/frank-m/alfred-rdp-workflow/releases
