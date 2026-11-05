# Quickshell Wayland bar and conky desktop

This directory implements a Wayland bar and a conky-style desktop widget with
Quickshell, in one process.  Both were ported from a polybar/conky setup; the
ports keep the original metrics and styling.

```
shell.qml        entry point: profile detection, bar and conky windows
launch.sh        launcher (Wayland platform, 1:1 DPI, logging)
bar/             bar theme, font chain, layout and modules
conky/           conky desktop window, data sampling and rendering
```

The bar reproduces the original bar in physical pixels: bar height, font
sizes, font fallback, module spacing, colours, tags, click/scroll actions and
the systray reservation.  The conky port reproduces the desktop window
pixel-for-pixel: window geometry, Xft/DPI scaling, fonts, line baselines,
`${goto}` columns, `${hr}` rules, bars, graphs, colours and the 47% black
background.

Everything runs natively on Wayland.  Workspaces and the active window use
Hyprland's IPC, the keyboard layout comes from `hyprctl`, and the rest of the
bar (fonts, spacing, hardware modules, tray) is desktop-agnostic.

## Run

Use the included launcher:

```sh
~/.config/quickshell/launch.sh
```

`qs` is Quickshell's command-line program; `quickshell` is the binary it wraps.
Running `qs` directly works if the Qt platform and DPI are already correct, but
the launcher is preferred because it selects the platform and logs crashes.

The launcher selects `QT_QPA_PLATFORM=wayland` unless the environment already
sets one.  It also sets `QT_FONT_DPI=96` and `QT_SCALE_FACTOR=1`, because the
bar is written in physical pixels.  Without them Qt may apply a 1.25x/1.5x
scale (for example from the desktop's scale), and the bar will not be
pixel-identical.

The raw equivalent is:

```sh
QT_QPA_PLATFORM=wayland QT_FONT_DPI=96 QT_SCALE_FACTOR=1 qs -n
```

The launcher keeps stdout/stderr in `~/.cache/quickshell-launch.log`.

On Hyprland, add this to `hyprland.conf`:

```ini
exec-once = ~/.config/quickshell/launch.sh
```

## Profiles

The two original bars are reproduced with the same machine detection as
`~/bin/wpc`: `PC=laptop`/`PC=mainpc` when set, otherwise the presence of
`/sys/class/power_supply/BAT0`.

* mainpc: height 27, DejaVu 13px, left = workspaces + active window,
  right = filesystem + mpd + volume + keyboard + memory + temperature + cpu + date
* laptop: height 35, DejaVu 20px, center = battery, right block = backlight
  + the mainpc right block

The monitor is `HDMI-A-1` on mainpc and `eDP-1` on the laptop by default.  Set
`MONITOR` to override it; name prefixes are accepted, and the first screen is
used if nothing matches.

## Modules

* workspaces: driven by `Hyprland.workspaces`, with focused / occupied / urgent
  / empty styles, 2-space padding, click-to-focus and scrolling.  Workspaces
  1-10 are always shown (with placeholders for empty ones), matching the
  original tag strip; named and higher-numbered workspaces follow.
* active window: `%title:0:30:...%` truncation widened to
  `theme.window_title_max` (60) characters, from
  `Hyprland.activeToplevel` with a `hyprctl -j activewindow` fallback.
* filesystem: `/home`, mountinfo + statvfs percentages, unmounted fallback.
* mpd: `mpc` every second, `theme.music_label_max` (90) character label
  truncation, prev/stop/toggle/next
  zones (the control glyphs are dropped when no configured font has them).
* volume: default PipeWire sink, ALSA-style 10-cell bar with the original
  colour buckets, muted format and 2% per wheel notch.  High-resolution
  wheels/touchpads accumulate their small deltas first instead of applying a
  step to every event.
* keyboard: layout and lock state from `hyprctl -j devices`, Caps/Scroll
  indicators (num lock is blacklisted), with the original red indicator
  background/padding.
* memory/cpu/temperature/date: the same /proc and hwmon sources and rounding as
  the original bar.  Temperature uses `hwmon` from the environment, then the
  first (mainpc) / second (laptop) hwmon, then thermal_zone0.
* battery: the BAT0/ADP1 sysfs paths from the config, including the charging
  animation and the literal `%time%` in the full label.
* backlight (laptop, first in the right block): percentage and ramp icon from
  `amdgpu_bl1`; scrolling changes the brightness by 5% per notch.
* tray: 16px StatusNotifier icons, `(even(bar_height)-16)/2 + 5` spacing, right
  aligned, reserving the same width from the right block.  Left click on the
  network item and right click on any item open the app's DBusMenu; middle
  click is secondary activate and scrolling is forwarded to the item.

## Fonts

The port reads the original font stack from fontconfig at runtime:

* `DejaVuSans:pixelsize=10` (13px after polybar's DPI conversion; the laptop
  bar uses `pixelsize=16` -> 20px)
* `Siji:pixelsize=10`
* `FontAwesome:pixelsize=14` (18px after polybar's DPI conversion)

Polybar's effective size is `FC_SIZE / 72 * 96`, not the raw `pixelsize`
value.  The port asks `fc-match` for the matched font and applies the same
formula, so it also follows a custom fontconfig DPI.

A fourth font, selected by fontconfig with `:lang=ja:weight=demilight`, is
appended to the chain so Japanese window titles and mpd tags render instead of
disappearing.  Qt explicitly re-enables FreeType's CFF stem darkening, which
makes Noto CJK's Regular face look bold at bar sizes (Pango/cairo leaves it
off, which is why waybar looks lighter).  The fallback therefore selects the
DemiLight face by full name and renders unhinted.  It only receives codepoints
that none of the three configured fonts covers, so the original Latin and icon
rendering is unchanged.  Glyphs missing from every font in the chain are still
dropped, exactly like polybar does (for example the media-control icons and
the G-clef when the configured fonts lack them).

Kerning is disabled in the port because cairo (polybar) does not apply
kerning, while Qt does by default.

Note: the original `line-size = 2 2` is rejected by polybar 3.7.2 ("Unrecognized
unit '2'"), so polybar falls back to a line size of 0 and draws no underlines.
The port mirrors that behaviour.

## Requirements

`fontconfig` (`fc-match`) with a Japanese font installed for CJK text, `mpc`
(mpd), `stat`/`awk` (filesystem), `nmcli` for
the nm-applet signal icon, and `hyprctl` (part of Hyprland).  Audio uses
Quickshell's PipeWire service; the volume module hides when there is no default
PipeWire sink.  `qt6-gtk-platformtheme` is needed for the native tray menu and
tray icons to follow the GTK theme on Qt 6.

The systray is a StatusNotifier/SNI host.  Legacy XEmbed-only tray clients will
not appear in it; applications with SNI/appindicator support work normally.
nm-applet's appindicator icon can be a static app icon; in that case the tray
substitutes the `nm-signal-*` icon selected from the in-use Wi-Fi signal
reported by `nmcli`.  It uses the same thresholds as nm-applet's
`mobile_helper_get_quality_icon_name()` and the plain `nm-signal-XX` link icon,
not the `-secure` variant.
Tray menus are implemented with Quickshell's platform DBusMenu integration, so
`shell.qml` starts with `//@ pragma UseQApplication`.  `launch.sh` also selects
Qt's GTK platform theme (unless one is already configured), so the native menu
and tray icons use the same GTK theme and icon theme as the rest of the desktop
instead of Qt's light default palette and hicolor fallback.  Do not set
`QS_ICON_THEME` unless you intentionally want to override the GTK theme: the
gsettings value can differ from the theme GTK actually uses.  If
`QT_QPA_PLATFORMTHEME` is set to something else in your session, that choice
is respected.  Tooltips are not implemented.

## Troubleshooting

* `Failed to compute left/right minimum bearings for "Siji"`: a Qt warning
  produced by the Siji bitmap font while measuring text.  It does not affect
  layout and is safe to ignore.
* If the bar does not start, run `~/.config/quickshell/launch.sh --no-color`
  and inspect `~/.cache/quickshell-launch.log`.  A QML error, a missing
  `Quickshell.Hyprland` module or a layer-shell rejection will be logged there.
* The compositor must support `wlr-layer-shell` (Hyprland does).  Without it
  `PanelWindow` cannot reserve a bar area.

## Conky port

`conky/ConkyContent.qml` implements the conky layout; the port is
self-contained in `conky/` (`ConkyTheme.qml`, `ConkyFonts.qml`,
`ConkyData.qml`, `ConkyText.qml`, `ConkyBar.qml`, `ConkyGraph.qml`,
`ConkyHr.qml`, `conky_data.sh`, `conky_temps.sh`).  On mainpc, `shell.qml` loads
the port and draws it with a second `PanelWindow`; no extra process is started.

Enable/disable and placement:

* mainpc only: the whole port (window, fonts and data sampling) is behind a
  `Loader` that never activates on the laptop, even with `CONKY=1`
* `CONKY=0` disables it on mainpc; `CONKY=1` re-enables it there
* `CONKY_MONITOR=DP-4` selects the output explicitly.  Without it the window
  goes to the rightmost screen: the original config sets `xinerama_head = 2`,
  which is out of range on a two-head setup, so it ends up at the far right of
  the combined desktop.
* `CONKY_DPI=120` overrides the DPI used for conky's scaling (the default is
  120, matching the original `Xft.dpi`).
* `CONKY_IP_INTERVAL=300` sets how often (in seconds, minimum 10) the public
  IP is re-checked; the default is 300s (see Data).

### Geometry

Conky scales every layout value by `Xft.dpi / 96` (`dpi_scale()` in
`display-output.hh`), while fonts are point sizes resolved by Xft at the same
DPI.  With mainpc's `Xft.dpi: 120` the scale is 1.25:

* text area = `max(370, measured text width) + 1` wide and exactly the
  measured text height, scaled.  conky.conf's `minimum_height 600` is not
  applied: since the rows are dynamic (interfaces, drives), the window hugs
  its content instead of keeping an empty band at the bottom
* window = text area + 2 * (25 + 1) scaled (528 wide at Xft.dpi 120; the
  height depends on the rows that are currently drawn)
* window position = top-right, gap 45 scaled, minus the border: the window's
  right edge sits 24px from the screen edge when Xft.dpi is 120
* `${goto N}` is an absolute position inside the window (`N * 1.25`), not
  relative to the text margin - this is conky's own behaviour
* line baselines advance by the Xft ascent of the font selected at the line
  start and the descent of the font at its end; font switches keep the
  baseline at the tallest ascent seen so far, exactly like
  `draw_each_line_inner()`
* `${voffset}` only shifts the rest of its line (it is parsed as an integer,
  so `-5.5` becomes -5) and is included in the measured line height
* bars are outline + fill rectangles (a 1px outline spanning w+1 by h+1
  pixels); graphs are one 1px column per sample, newest at the right,
  auto-scaled to the maximum sample; `${hr h}` is a thick line from the text
  origin to the right edge of the text area

The text size is recomputed like `update_text_area()`: a sizing pass over every
line uses the previous frame's cursor for the `${goto}` comparison, so the
window settles on the same width conky reports.

### Fonts

The four fonts of the config (`Ubuntu Mono:size=8`,
`Conky Icons by Carelli:size={14,30,9}`) are resolved through `fc-match`, so
the port renders with the same font files fontconfig would give conky.  For
each font:

* the conky pixel size is `size * dpi / 72` (8pt at 120dpi = 13.333px)
* Qt's integral pixel size is used for rendering (`round(13.333) = 13`)
* ascent/descent are recomputed as `ceil(scaled ascender/descender)`, which is
  what Xft uses (font0: 15/4, Carelli 14: 22/2, Carelli 30: 47/4,
  Carelli 9: 15/1)
* glyph advances are rounded per glyph, matching Xft's integer positioning;
  `letterSpacing` makes Qt's run width match exactly (exact for the monospace
  default font)
* `xftalpha = 0.8` is applied to font 0 only, like `text_alpha`

Qt rasterises glyphs with grayscale antialiasing at 13px, Xft at 13.333px with
subpixel antialiasing, so individual glyphs can differ by a pixel even though
the positions, baselines, sizes and colours match.  That is a limitation of
text rendering in Qt Quick, not of the layout.

### Data

`conky/conky_data.sh` is sampled every second and parsed by
`conky/ConkyData.qml`, which implements conky's update and formatting rules
(uptime format, `format_human_readable()` with the locale decimal separator,
diskio averages over `diskio_avg_samples`, net averages over `net_avg_samples`,
CPU usage averaged over `cpu_avg_samples`, `round_to_positive_int()` for
percentages, truncated `fs_used_perc`, `top` name/pid/cpu from the CPU-sorted
list and `top mem` from the memory-sorted list with conky's `%6.2f`/`%7i`
padding).

Sources: `/proc/uptime`, `/etc/os-release`, `uname -r`, `/proc/net/dev`,
`ip -4 -o addr`, `ip route show default`, `/sys/class/net`, `/proc/net/wireless`
(plus `iwgetid`/`iw` when available), `curl ifconfig.co` (the config's
`${exec}`), `stat -f` for the file systems, `/proc/diskstats`, `/sys/block`,
`/proc/stat`, `/proc/meminfo` and `/proc/<pid>/stat`.  Drive temperatures come
from `conky_temps.sh` on its own 5s timer (the hddtemp daemon on
`127.0.0.1:7634` through bash's `/dev/tcp`, plus the hwmon sensors of the
disks); see below.

### Networks and disks

The original `conky.conf` hardcoded `wlp6s0`, `enp7s0`, `nvme0n1` and `sdb`.
`conky_data.sh` detects them instead:

* the first physical wireless interface (has `wireless` or `phy80211`) and the
  first physical wired one (has a `device` link and no `wireless`), each only
  when it is actually up (`operstate`, `carrier`, or holding an IPv4 address).
  They are reported as `netif=wlan <dev>` / `netif=eth <dev>` and the samples
  are taken for those devices only.
* the layout draws the WLAN/ETH columns from those lines: both columns when
  both are up, a single column at `goto 85` when only one is, and no network
  lines at all (ESSID included) when neither is.  The public IP line stays.
* the byte counters come from `/proc/net/dev`, which pads the interface name
  with `%6s`: `lo`/`eth0` carry two extra leading blanks that `wlp6s0`/
  `enp7s0` do not, so the field numbers are not fixed per interface.  The
  parser strips the padding and cuts at the `:` instead.  `ConkyData.qml`
  turns the counters into `${downspeed}`/`${upspeed}` following
  `net_avg_samples` (2), i.e. the average of the last two one-second deltas.
* the ESSID row is `${wireless_essid} : ${wireless_link_qual_perc}%`.  The
  percentage is computed like conky does (`quality / max_qual`, with 70 as the
  mac80211 maximum).  When a driver reports no quality, the standard dBm
  mapping is used instead (0..100% for -100..-50 dBm), and `iw dev ... link`
  supplies the level when `/proc/net/wireless` is empty; a level that is 0 or
  below -110 dBm is the driver's "unknown" marker (-256 on mac80211) and is
  ignored.  `/proc/net/wireless` has the same `%6s` padding as `/proc/net/dev`.
* disk I/O is read for every physical disk under `/sys/block`.  Partitions,
  `loop`/`ram`/`zram` devices and `dm`/`md` mappings are skipped so that each
  I/O is counted once, at the real disk.  The per-device `nvme0n1`/`sdb` rows
  are gone: the `Read:`/`Write:` rows and their graphs show all drives
  together (`disks.total` in `ConkyData.qml`).
* drive temperatures are listed dynamically, one `dev: NN ºC` cell per drive,
  joined by two spaces.  `conky_temps.sh` asks the hddtemp daemon and reads
  each physical disk's `hwmon` sensor (`/sys/block/<dev>/device/hwmon*/` or the
  namespace parent, so both `drivetemp` for ATA/SATA and the nvme driver's
  controller sensor are found), de-duplicated by device.  Drives without a
  reading are skipped, and the row disappears when no drive reports one.

Conky runs `${exec curl ...}` on every update; the port does not.  The public IP
is looked up only when

* it is still unknown (startup, or no lookup has succeeded yet),
* the network changed (interface addresses, default route or link state
  differs from the previous sample), or
* the last successful lookup is older than `ip_refresh_interval` (5 minutes by
  default, `CONKY_IP_INTERVAL=<seconds>` to override).

A failed lookup keeps the last known address and is retried after 30 seconds
instead of every second, and a lookup whose result arrives after the network
changed is discarded (the change is re-checked on the next tick).

### Differences from conky

* The window is a layer-shell surface in the bottom layer
  (`aboveWindows: false`), which is how a desktop window is approximated on
  Wayland.  Conky originally used a desktop window.
* Text uses Qt's grayscale glyph rasteriser instead of Xft's subpixel one, and
  at the nearest integral pixel size (see Fonts).
* The window background is `#78000000`, the same ARGB colour conky fills.
  Transparency (background and the 0.8 text alpha) is handled by the Wayland
  compositor.

### Requirements

fontconfig (`fc-match`), `curl`, `ip` (iproute2), `stat`, `getconf`, `awk`,
`bash` (for `/dev/tcp`).  `iwgetid` or `iw` are optional (ESSID, and the
signal level when `/proc/net/wireless` is empty).  The hddtemp
daemon and the `drivetemp` kernel module are optional (drive temperatures).
NVMe temperatures work out of the box through the nvme driver's own hwmon
sensor; for ATA/SATA disks either the hddtemp daemon or `drivetemp` is needed
(`modprobe drivetemp`, or `drivetemp` in `/etc/modules-load.d/` to load it at
boot).  If `fc-match` cannot find the configured fonts, the port
renders with whatever fontconfig substitutes, exactly like conky.
