# Startup and display troubleshooting

## Startup commands

[`lua/autostart.lua`](../lua/autostart.lua) registers commands on
`hyprland.start`. Loading or reloading the config does not relaunch these apps.

Enabled on both machine profiles:

- `hypridle`
- Xresources loading with `xrdb`
- Signal
- MPD restart followed by `mpDris2`
- `nm-applet`

`ckb-next -b` also starts on `mainpc`. The wallpaper daemon, bar, notification
daemon, clipboard watcher, Conky, and MEGAsync entries remain commented out.

## Signal's small text at login

The installed Signal wrapper forces `--ozone-platform=x11`, so Signal uses
XWayland. Its initial scaling can depend on the Xresources DPI available when
Electron starts. `QT_FONT_DPI` does not configure Electron.

The original config launched Signal before loading Xresources. Restarting Signal
after the resources were loaded would explain the return to normal text size.
The reference dotfiles set `Xft.dpi: 120`; check the live session rather than
assuming the installed resources match that reference.

Xrdb and Signal retain **separate exec calls**, now ordered by completion rather
than merely by invocation. `hl.exec_cmd` is asynchronous and provides no process
completion callback in this version. The xrdb shell therefore notifies Lua over
Hyprland IPC after xrdb exits successfully:

```lua
hl.exec_cmd([[xrdb -merge "$HOME/.Xresources" && hyprctl eval 'require("lua/autostart").after_xresources()']])
```

The module's `after_xresources()` callback launches Signal separately:

```lua
hl.exec_cmd("signal-desktop")
```

Signal is not part of the xrdb shell command. The `&&` gates only the completion
notification; Signal's own exec cannot occur until that notification reaches
Lua. `hyprctl` inherits the compositor instance environment. Resolving the
callback through `require` also allows a pending completion to reach the current
module if the config reloads while xrdb is running. A module-local guard ignores
repeated callbacks within the same Lua state.

This avoids arbitrary delays, polling, and blocking the compositor with
`os.execute` or a synchronous pipe read (XWayland may need the compositor's event
loop to make progress). Other startup apps remain independent. No forced zoom
or backend change is added.

If xrdb or its IPC notification fails, Signal does not autostart. Check the
command's error output and Xresources, then launch Signal manually after fixing
the failure.

To inspect the live settings:

```sh
xrdb -query | grep Xft.dpi
```

For a manual check, load the resources, fully quit Signal, then reopen it:

```sh
xrdb -merge "$HOME/.Xresources"
```

The callback now provides that completion ordering automatically at startup.
The visual result still needs confirmation in a fresh live session.

## Tiled terminal looks less transparent until reload

There is no monitor-specific terminal opacity rule in this config. In Hyprland
0.56.2, ordinary tiled windows can use a cached background blur, while floating
windows normally sample the live scene. A stale startup background in that cache
can resemble different opacity or the wrong wallpaper. Reloading invalidates
cached blur, which fits the reported symptom; this has not been visually
confirmed in the sandbox.

[`lua/rules.lua`](../lua/rules.lua) supplies the targeted workaround:

```lua
hl.window_rule({
    name  = "alacritty-live-blur",
    match = { class = "(?i)^(alacritty|floating)$", float = false },
    xray  = false,
})
```

The explicit per-window `xray = false` bypasses the tiled background cache.
Global `decoration.blur.xray = false` alone does not do so in this version.

The rule covers tiled Alacritty windows on either monitor, including a terminal
started with `--class floating` and subsequently tiled. It preserves blur and
the terminal's own opacity. Floating windows, other apps, wallpaper selection,
and monitor/HDR settings are unchanged. No automatic reload is scheduled.

Live blur can cost more GPU work than cached blur. Other apps retain their
normal optimization. The monocle module already uses live blur for its tiles;
Alacritty now also retains live blur when returning to ordinary tiling.
Remove the `alacritty-live-blur` rule to revert this workaround.

## Validation

Run from `~/.config/hypr`:

```sh
python3 tests/autostart_test.py
lua tests/rules_test.lua
luajit tests/rules_test.lua
Hyprland --verify-config -c "$HOME/.config/hypr/hyprland.lua"
```

The startup test executes the configured shell command with stub xrdb/IPC
clients, then evaluates its actual Lua callback against a mock `hl` API. It
checks deferred launch, success/failure ordering, Signal's separate exec,
duplicate callbacks, reload while completion is pending, both machine profiles,
and no launch during config loading. It does not contact the real IPC socket.
The rules test checks the blur workaround's scope, not GPU output.

The sandbox cannot access the live compositor, X server, or installed
`~/bin/wpc`. Offline native config validation therefore uses an isolated HOME
with a fixture `bin/wpc` for each machine profile.

On the desktop:

1. Reload once with **Super+Escape** to apply the terminal rule.
2. At the next fresh login, check Signal's initial text size before restarting it.
3. Open a terminal on the left monitor and toggle tiled/floating without a reload.
4. Compare both monitors and check whether reloading still changes the background
   visible through the terminal.
