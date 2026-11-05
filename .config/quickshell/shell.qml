//@ pragma UseQApplication

import Quickshell
import Quickshell.Io
import QtQuick
import "bar"
import "conky"

ShellRoot {
  id: shell

  // Same machine detection as ~/bin/wpc:
  // laptop if /sys/class/power_supply/BAT0 exists, otherwise mainpc.
  property bool laptop: false
  property bool profile_ready: false

  Component.onCompleted: {
    const pc = Quickshell.env("PC");
    if (pc === "laptop") {
      shell.laptop = true;
      shell.profile_ready = true;
    } else if (pc === "mainpc") {
      shell.laptop = false;
      shell.profile_ready = true;
    } else {
      detect.running = true;
    }
  }

  Process {
    id: detect
    command: ["sh", "-c", "test -d /sys/class/power_supply/BAT0"]
    onExited: function(code) {
      shell.laptop = (code === 0);
      shell.profile_ready = true;
    }
  }

  Theme {
    id: theme
    laptop: shell.laptop
  }

  // The conky desktop window is mainpc only (like `$mainpc && conky -q`).
  // It is never enabled on the laptop, even with CONKY=1.
  readonly property bool conky_enabled: !shell.laptop
    && Quickshell.env("CONKY") !== "0"

  // conky scales its layout by dpi / 96.  The original mainpc setup used 120;
  // CONKY_DPI overrides it.
  readonly property int conky_dpi: {
    const value = parseInt(Quickshell.env("CONKY_DPI"));
    if (!isNaN(value) && value > 0) return value;
    return 120;
  }

  // conky.conf sets xinerama_head = 2, which is out of range on a two-head
  // setup: conky then keeps the whole display as its work area and ends up at
  // the far right of the combined desktop.  Do the same (rightmost screen).
  readonly property var conky_screen: {
    const list = Quickshell.screens;
    if (!list || list.length === 0) return null;

    const wanted = Quickshell.env("CONKY_MONITOR");
    if (wanted) {
      for (let i = 0; i < list.length; ++i)
        if (list[i].name === wanted) return list[i];
      for (let i = 0; i < list.length; ++i)
        if (list[i].name.indexOf(wanted) === 0) return list[i];
    }

    let best = list[0];
    for (let i = 1; i < list.length; ++i)
      if (list[i].x + list[i].width > best.x + best.width) best = list[i];
    return best;
  }

  FontChain {
    id: fonts
    laptop: shell.laptop
    active: shell.profile_ready
    bar_height: theme.bar_height
  }

  readonly property var bar_screen: {
    const list = Quickshell.screens;
    if (!list || list.length === 0) return null;

    let wanted = Quickshell.env("MONITOR");
    if (!wanted) wanted = theme.default_monitor;

    for (let i = 0; i < list.length; ++i) {
      if (list[i].name === wanted) return list[i];
    }
    for (let i = 0; i < list.length; ++i) {
      if (list[i].name.indexOf(wanted) === 0) return list[i];
    }
    return list[0];
  }

  // PanelWindow maps to wlr-layer-shell on Wayland, so the bar reserves an
  // exclusive zone like a native panel.
  PanelWindow {
    id: window

    visible: shell.profile_ready
    screen: shell.bar_screen

    anchors {
      top: true
      left: true
      right: true
    }

    implicitHeight: theme.bar_height
    exclusiveZone: theme.bar_height
    color: theme.background
    aboveWindows: true
    focusable: false

    Bar {
      anchors.fill: parent
      theme: theme
      fonts: fonts
    }
  }

  // Pixel-perfect port of ~/.config/conky/conky.conf (mainpc, rightmost
  // screen).  Conky's window is a desktop window: background layer, no input.
  // The whole port is only instantiated on mainpc, so the laptop never starts
  // the sampling processes or renders it.
  Loader {
    id: conky_loader
    active: shell.profile_ready && shell.conky_enabled

    sourceComponent: Component {
      Item {
        ConkyTheme {
          id: conky_theme
          dpi: shell.conky_dpi
        }

        ConkyFonts {
          id: conky_fonts
          theme: conky_theme
        }

        ConkyData {
          id: conky_data
          theme: conky_theme
        }

        PanelWindow {
          id: conky_window

          visible: conky_fonts.ready && conky_data.ready
          screen: shell.conky_screen
          color: conky_theme.background
          exclusiveZone: 0
          exclusionMode: ExclusionMode.Ignore
          focusable: false
          aboveWindows: false

          anchors.top: true
          anchors.right: true
          margins.top: Math.max(0, conky_theme.dpi_scale(conky_theme.gap_y) - conky_content.border)
          margins.right: Math.max(0, conky_theme.dpi_scale(conky_theme.gap_x) - conky_content.border)
          implicitWidth: conky_content.frame.width + 2 * conky_content.border
          implicitHeight: conky_content.frame.height + 2 * conky_content.border

          ConkyContent {
            id: conky_content
            width: conky_window.width
            height: conky_window.height
            theme: conky_theme
            fonts: conky_fonts
            source: conky_data
          }
        }
      }
    }
  }
}
