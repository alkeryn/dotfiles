import QtQuick
import Quickshell.Hyprland
import Quickshell.Io

// [module/xwindow] for Hyprland: the same + "..." truncation as polybar's
// %title:0:30:...% token, widened to theme.window_title_max characters.
// Hyprland.activeToplevel is used when it has a title; hyprctl covers cases
// where the toplevel-mapping protocol is unavailable or the active toplevel
// has not been associated yet.
Item {
  id: root

  required property var theme
  required property var fonts

  property string fallback_title: ""

  implicitHeight: theme.bar_height
  readonly property string title: {
    const t = Hyprland.activeToplevel ? Hyprland.activeToplevel.title : "";
    return (t !== undefined && t !== null && ("" + t).length > 0) ? ("" + t) : fallback_title;
  }
  readonly property bool has_content: title !== ""
  readonly property string shown_title: theme.truncate_token(title, theme.window_title_max, "...")
  readonly property real text_width: text.implicitWidth

  width: text_width
  implicitWidth: text_width

  Process {
    id: active_window
    command: ["hyprctl", "-j", "activewindow"]
    stdout: StdioCollector {
      id: active_window_out
      onStreamFinished: {
        try {
          const data = JSON.parse(active_window_out.text);
          root.fallback_title = (data && data.title) ? ("" + data.title) : "";
        } catch (e) {
          root.fallback_title = "";
        }
      }
    }
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  function refresh() {
    if (active_window.running) return;
    active_window.running = true;
  }

  Component.onCompleted: refresh()

  PolyText {
    id: text
    visible: root.has_content
    theme: root.theme
    fonts: root.fonts
    segments: [{ text: root.shown_title, color: root.theme.foreground }]
  }
}
