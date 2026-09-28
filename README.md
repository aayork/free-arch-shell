# Roseshell

Roseshell is a fork of the [Omarchy](https://omarchy.org) shell, meant to be
installed on other distros.

Omarchy is DHH's Arch-based Linux distribution, and its desktop is a
[Quickshell](https://quickshell.org/) shell for [Hyprland](https://hypr.land/)
that normally only runs as part of an Omarchy install. Roseshell takes that
shell out on its own, so you can run it on your existing system instead of
installing Omarchy: any distro with Hyprland, Quickshell and systemd. It was
built on CachyOS, and nothing it runs is tied to Arch or its package manager.

One long-running Quickshell process hosts the whole desktop: the top bar, the
lock screen, notifications, on-screen displays, the wallpaper, the idle
screensaver, and the panels behind the bar's icons. Each of those is a plugin,
and third-party plugins load from disk the same way.

## What's in it

- **Bar**: workspaces, clock with a world-clock popup, calendar, tray, audio,
  Bluetooth, network, Tailscale and more. It can be solid or transparent, and
  it hides over fullscreen apps: touch the top edge and it slides down, like
  the macOS menu bar.
- **Panels**: audio devices and volume, Wi-Fi (including a QR code to share
  the network), Bluetooth, power profiles and system stats, weather, and
  network and disk speed tests.
- **Calendar**: iCloud CalDAV sync and ICS feed subscriptions.
- **Lock screen and idle**: screensaver, then lock, then screen off. The
  screensaver plays Apple aerial videos with mpv, and it holds off while media
  is playing or a window is fullscreen.
- **Theming**: 20+ themes in `themes/`, plus a Settings panel for theme, font,
  cursor and icon theme. It can generate a theme from the wallpaper's colours,
  and it passes theme colours on to apps such as Zen Browser and termusic.
- **Notifications, clipboard history, emoji picker, reminders, polkit agent.**
- **Plugins**: `roseshell-plugin add|enable|disable|remove|list` installs and
  manages third-party plugins in `~/.config/roseshell/plugins/`. Plugins written
  for Omarchy's shell generally work. The Omacast launcher is one of them, and
  `bin/roseshell-vim-keys` adds a `vim:` search to it for your Neovim
  keybindings and Vim's built-in commands.

## How it differs from Omarchy

- **Installs on other distros.** It runs on plain Hyprland with a Lua config,
  with no Omarchy install underneath. It does not need UWSM: every launch uses
  `uwsm-app` when it is there and starts the app directly when it is not.
- **Renamed throughout.** Commands, IPC targets, window classes and config
  paths use `roseshell` (`roseshell-*` scripts, `~/.config/roseshell/`,
  `ROSESHELL_PATH`).
- **Only the shell.** Omarchy's installer, package management, update
  channel, migrations and bundled apps are left out. (The Omarchy system menu
  is still in `shell/plugins/menu/`, but its install and remove entries assume
  Arch's `pacman` and are not used.)
- **Fork-only features**: the aerial screensaver, the fullscreen bar peek, the
  calendar plugin, the Settings panel and the wallpaper theme generator.

## Repository layout

This repository keeps Omarchy's full history and tree so upstream fixes can
still be merged in (`git fetch upstream && git merge upstream/quattro`).
Roseshell is the part that runs:

| Path | What it is |
| --- | --- |
| `shell/` | The Quickshell shell: `shell.qml`, services, and first-party plugins. See [`shell/README.md`](shell/README.md). |
| `bin/roseshell-*` | The scripts the shell calls (network, audio, themes, idle, lock, ...). |
| `config/`, `default/` | The default `shell.json`, the icon font, and the `vim:` Omacast extension. |
| `themes/` | Theme packages: colours, wallpapers and per-app theme files. |

Everything else (`install/`, `migrations/`, `manual/`, and the `bin/omarchy-*`
scripts) is upstream Omarchy, kept for merging and not used by Roseshell.
A sparse checkout of just the paths above is enough to run it:

```sh
git clone --filter=blob:none --sparse https://github.com/aayork/roseshell ~/projects/roseshell
cd ~/projects/roseshell
git sparse-checkout set /shell /bin /config /default /themes /README.md /LICENSE
```

## Running it

You need:

- Hyprland (a version with the Lua config), Quickshell, and systemd
- NetworkManager (`nmcli`), BlueZ (`bluetoothctl`), PipeWire (`wpctl`)
- `jq`, `curl`, `wl-clipboard`, `wtype`, `playerctl`, `brightnessctl`
- a [Nerd Font](https://www.nerdfonts.com/)

Some features need a little more: `mpv` for the aerial screensaver,
`qrencode` for the Wi-Fi QR code, `hyprsunset` for night light,
`power-profiles-daemon` and `upower` for the power panel, and `tailscale` for
the Tailscale panel. The package names are much the same on every distro.

1. Put the scripts on your `PATH`, for example by symlinking
   `bin/roseshell-*` into `~/.local/bin`.
2. Tell the shell where it lives, and launch it from Hyprland's autostart. In
   `hyprland.lua`:

   ```lua
   local roseshellPath = os.getenv("HOME") .. "/projects/roseshell"

   hl.env("ROSESHELL_PATH", roseshellPath)
   hl.env("PATH", os.getenv("HOME") .. "/.local/bin:" .. (os.getenv("PATH") or "/usr/local/bin:/usr/bin"))

   hl.on("hyprland.start", function()
     hl.exec_cmd("systemctl --user import-environment ROSESHELL_PATH")
     hl.exec_cmd(roseshellPath .. "/bin/roseshell-launch-shell")
   end)
   ```

   Hyprland applies `hl.env` only when it starts, so log out and back in after
   changing these lines.
3. Configure the bar layout, idle timings and plugins in
   `~/.config/roseshell/shell.json`. `config/roseshell/shell.json` is the
   default to start from.

`roseshell-restart-shell` restarts the shell, and `roseshell-shell` sends IPC
calls to the running one:

```sh
roseshell-shell shell summon roseshell.network    # open the network panel
roseshell-shell idle status
```

The shell logs to the journal: `journalctl --user -t roseshell-shell`.

## Credits and license

Roseshell is built on Omarchy by David Heinemeier Hansson and its contributors,
and is released under the same [MIT license](LICENSE).
