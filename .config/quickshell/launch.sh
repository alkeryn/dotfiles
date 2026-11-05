#!/usr/bin/env bash
# Launch the Quickshell bar.
#
# The bar is written in physical pixels.  Qt scales windows and fonts by the
# session's DPI/scale, so pin its DPI/scale to 1:1 to keep the layout exact,
# regardless of whether the session uses 96, 120 or 150.
export QT_FONT_DPI=96
export QT_SCALE_FACTOR=1

# Let Qt (and therefore the native tray menus) use the session's GTK theme
# instead of Qt's default light Fusion palette.  This also makes QIcon resolve
# tray icons in the same icon theme as the rest of the desktop.  An explicit
# platform theme chosen by the user still wins.
if [ -z "${QT_QPA_PLATFORMTHEME:-}" ]; then
  export QT_QPA_PLATFORMTHEME=gtk3
fi

# Do not force QS_ICON_THEME here.  Qt's GTK platform theme already selects
# the same icon theme as GTK/nm-applet; overriding it with the gsettings value
# can pick a different theme (for example Adwaita instead of the GTK theme
# Xenlism) and make the tray icon differ from the rest of the desktop.

# Always use a native Wayland surface.  An explicit QT_QPA_PLATFORM still wins.
if [ -z "${QT_QPA_PLATFORM:-}" ]; then
  export QT_QPA_PLATFORM=wayland
fi

# Stop an old Quickshell instance so it does not keep an exclusive zone.
pkill -x qs 2>/dev/null || true
pkill -x quickshell 2>/dev/null || true

# Keep stderr/stdout so a startup crash or QML error can be inspected later.
log="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell-launch.log"
mkdir -p "$(dirname "$log")" 2>/dev/null || true
exec > >(tee -a "$log") 2>&1
printf '\n=== %s ===\n' "$(date -Is 2>/dev/null || date)"

exec qs -n "$@"
