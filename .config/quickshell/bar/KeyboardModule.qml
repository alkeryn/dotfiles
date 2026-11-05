import QtQuick
import Quickshell.Io

// [module/xkeyboard]
// blacklist-0 = num lock
// format-prefix = <siji E26F + space>, label-layout = %layout%
// label-indicator-padding = 2, label-indicator-margin = 1,
// label-indicator-background = secondary
//
// The layout and lock state come from `hyprctl -j devices`.
Item {
  id: root

  required property var theme
  required property var fonts

  implicitHeight: theme.bar_height
  width: content.implicitWidth
  implicitWidth: width

  property string layout: ""
  property bool caps_lock: false
  property bool scroll_lock: false

  readonly property real margin: fonts.advance(0, " ")
  readonly property real pad: fonts.advance(0, "  ")

  function update(raw) {
    let data;
    try {
      data = JSON.parse(raw);
    } catch (e) {
      return;
    }
    const keyboards = data.keyboards || [];
    let kb = null;
    for (let i = 0; i < keyboards.length; ++i) {
      if (keyboards[i].main) {
        kb = keyboards[i];
        break;
      }
    }
    if (!kb) kb = keyboards[0];
    if (!kb) {
      root.layout = "";
      root.caps_lock = false;
      root.scroll_lock = false;
      return;
    }
    const layout = kb.layout || kb.active_keymap || "";
    root.layout = ("" + layout).split(",")[0];
    root.caps_lock = !!kb.capsLock;
    root.scroll_lock = !!kb.scrollLock;
  }

  Process {
    id: reader
    command: ["hyprctl", "-j", "devices"]
    stdout: StdioCollector {
      id: reader_out
      onStreamFinished: root.update(reader_out.text)
    }
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!reader.running) reader.running = true
  }

  Row {
    id: content
    spacing: 0

    PolyText {
      theme: root.theme
      fonts: root.fonts
      segments: [
        { text: "\ue26f ", color: root.theme.foreground_alt },
        { text: root.layout, color: root.theme.foreground }
      ]
    }

    // the literal space in "<label-layout> <label-indicator>"
    Item {
      visible: root.caps_lock || root.scroll_lock
      width: visible ? root.fonts.advance(0, " ") : 0
      height: root.theme.bar_height
    }

    Item {
      visible: root.caps_lock
      width: visible ? (root.margin + root.pad * 2 + root.fonts.advance(0, "Caps Lock") + root.margin) : 0
      height: root.theme.bar_height

      Rectangle {
        x: root.margin
        width: root.pad * 2 + root.fonts.advance(0, "Caps Lock")
        height: root.theme.bar_height
        color: root.theme.secondary
      }
      PolyText {
        x: root.margin + root.pad
        theme: root.theme
        fonts: root.fonts
        segments: [{ text: "Caps Lock", color: root.theme.foreground }]
      }
    }

    Item {
      visible: root.scroll_lock
      width: visible ? (root.margin + root.pad * 2 + root.fonts.advance(0, "Scroll Lock") + root.margin) : 0
      height: root.theme.bar_height

      Rectangle {
        x: root.margin
        width: root.pad * 2 + root.fonts.advance(0, "Scroll Lock")
        height: root.theme.bar_height
        color: root.theme.secondary
      }
      PolyText {
        x: root.margin + root.pad
        theme: root.theme
        fonts: root.fonts
        segments: [{ text: "Scroll Lock", color: root.theme.foreground }]
      }
    }
  }
}
