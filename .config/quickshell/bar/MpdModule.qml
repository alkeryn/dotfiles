import QtQuick
import Quickshell
import Quickshell.Io

// [module/mpd]
// format-online = <label-song> <icon-prev> <icon-stop> <toggle> <icon-next>
// label-song = <g-clef> %title% - %artist%   (maxlen theme.music_label_max,
// ellipsis)
Item {
  id: root

  required property var theme
  required property var fonts

  implicitHeight: theme.bar_height
  width: content.implicitWidth
  implicitWidth: width

  property string state: ""
  property string title: ""
  property string artist: ""

  readonly property bool connected: state !== ""
  readonly property bool show_label: connected && state !== "stopped"
  readonly property string song_label: {
    const raw = "\u{1d11e} " + (title !== "" ? title : "untitled track") +
                " - " + (artist !== "" ? artist : "untitled artist");
    return theme.truncate(raw, theme.music_label_max);
  }
  readonly property string toggle_icon: state === "playing" ? "\u23f8" : "\u23f5"

  function update(raw) {
    const lines = raw.split("\n");
    const song = lines.length > 0 ? lines[0] : "";
    const parts = song.split("\t");
    root.title = parts.length > 0 ? parts[0] : "";
    root.artist = parts.length > 1 ? parts[1] : "";

    let state = "";
    for (let i = 1; i < lines.length; ++i) {
      const m = lines[i].match(/^\[([a-z]+)\]/);
      if (m) { state = m[1]; break; }
    }
    root.state = state;
  }

  function command(args) {
    Quickshell.execDetached(["mpc"].concat(args));
  }

  Process {
    id: reader
    command: ["sh", "-c", "mpc status -f '%title%\t%artist%' 2>/dev/null"]
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
      segments: [{ text: root.show_label ? root.song_label : "", color: root.theme.foreground }]
    }

    // literal spaces in the format string survive even when the control icon
    // glyph itself is missing from the configured fonts
    Item { width: root.fonts.advance(0, " "); height: root.theme.bar_height }

    Item {
      width: prev_text.implicitWidth
      height: root.theme.bar_height
      PolyText {
        id: prev_text
        theme: root.theme
        fonts: root.fonts
        segments: [{ text: "\u23ee", color: root.theme.foreground }]
      }
      MouseArea {
        anchors.fill: parent
        enabled: parent.width > 0
        acceptedButtons: Qt.LeftButton
        onClicked: root.command(["prev"])
      }
    }

    Item { width: root.fonts.advance(0, " "); height: root.theme.bar_height }

    Item {
      width: stop_text.implicitWidth
      height: root.theme.bar_height
      PolyText {
        id: stop_text
        theme: root.theme
        fonts: root.fonts
        segments: [{ text: "\u23f9", color: root.theme.foreground }]
      }
      MouseArea {
        anchors.fill: parent
        enabled: parent.width > 0
        acceptedButtons: Qt.LeftButton
        onClicked: root.command(["stop"])
      }
    }

    Item { width: root.fonts.advance(0, " "); height: root.theme.bar_height }

    Item {
      width: toggle_text.implicitWidth
      height: root.theme.bar_height
      PolyText {
        id: toggle_text
        theme: root.theme
        fonts: root.fonts
        segments: [{ text: root.toggle_icon, color: root.theme.foreground }]
      }
      MouseArea {
        anchors.fill: parent
        enabled: parent.width > 0
        acceptedButtons: Qt.LeftButton
        onClicked: root.command(["toggle"])
      }
    }

    Item { width: root.fonts.advance(0, " "); height: root.theme.bar_height }

    Item {
      width: next_text.implicitWidth
      height: root.theme.bar_height
      PolyText {
        id: next_text
        theme: root.theme
        fonts: root.fonts
        segments: [{ text: "\u23ed", color: root.theme.foreground }]
      }
      MouseArea {
        anchors.fill: parent
        enabled: parent.width > 0
        acceptedButtons: Qt.LeftButton
        onClicked: root.command(["next"])
      }
    }
  }
}
