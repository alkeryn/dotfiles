import QtQuick
import Quickshell
import Quickshell.Io

// [module/temperature]
// format = <ramp> <label>, warn-temperature = 60
Item {
  id: root

  required property var theme
  required property var fonts

  implicitHeight: theme.bar_height
  width: text.implicitWidth
  implicitWidth: width

  property bool available: false
  property int temperature: 0
  property string path: ""

  function update(raw) {
    const out = raw.trim();
    if (!out) {
      root.available = false;
      return;
    }
    const milli = parseInt(out, 10);
    if (isNaN(milli) || milli === 0) {
      root.available = false;
      return;
    }
    root.temperature = Math.round(milli / 1000);
    root.available = true;
  }

  Process {
    id: path_finder
    command: ["sh", "-c", "ls -1 /sys/class/hwmon/hwmon*/temp1_input 2>/dev/null"]
    stdout: StdioCollector {
      id: path_out
      onStreamFinished: {
        const env_path = Quickshell.env("hwmon");
        let chosen = env_path ? env_path : "";
        if (!chosen) {
          const paths = path_out.text.split("\n").filter(function(p) { return p.trim().length > 0; });
          if (paths.length > 0) {
            chosen = root.theme.laptop ? (paths.length > 1 ? paths[1] : "") : paths[0];
          }
        }
        if (!chosen) chosen = "/sys/class/thermal/thermal_zone0/temp";
        root.path = chosen;
        if (!reader.running) reader.running = true;
      }
    }
  }

  Process {
    id: reader
    command: ["cat", root.path]
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
    onTriggered: {
      if (root.path === "") {
        if (!path_finder.running) path_finder.running = true;
      } else if (!reader.running) {
        reader.running = true;
      }
    }
  }

  readonly property string ramp: temperature <= 0 ? "\ue0c9" : temperature >= 60 ? "\ue0cb" : "\ue0ca"
  readonly property color label_color: temperature >= 60 ? theme.secondary : theme.foreground

  PolyText {
    id: text
    visible: root.available
    theme: root.theme
    fonts: root.fonts
    segments: [
      { text: root.ramp, color: root.theme.foreground_alt },
      { text: " " + root.temperature + "\u00b0C", color: root.label_color }
    ]
  }
}
