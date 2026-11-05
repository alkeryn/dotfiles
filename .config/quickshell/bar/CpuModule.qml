import QtQuick
import Quickshell.Io

// [module/cpu]
// format-prefix = <siji E026>, label = %percentage%%
Item {
  id: root

  required property var theme
  required property var fonts

  implicitHeight: theme.bar_height
  width: text.implicitWidth
  implicitWidth: width

  property string value: "0%"
  property var previous: []

  function parse(raw) {
    const cores = [];
    const lines = raw.split("\n");
    for (let i = 0; i < lines.length; ++i) {
      const line = lines[i];
      if (line.indexOf("cpu") !== 0 || line.indexOf("cpu ") === 0) continue;
      const parts = line.trim().split(/\s+/);
      if (parts.length < 9) continue;
      const user = parseInt(parts[1], 10);
      const nice = parseInt(parts[2], 10);
      const system = parseInt(parts[3], 10);
      const idle = parseInt(parts[4], 10);
      const steal = parseInt(parts[8], 10);
      cores.push({
        idle: idle,
        total: user + nice + system + idle + steal
      });
    }
    return cores;
  }

  function update(raw) {
    const current = parse(raw);
    if (current.length === 0) return;

    if (previous.length === current.length) {
      let sum = 0;
      for (let i = 0; i < current.length; ++i) {
        const diff = current[i].total - previous[i].total;
        if (diff <= 0) continue;
        let load = 100 * (diff - (current[i].idle - previous[i].idle)) / diff;
        load = Math.min(100, Math.max(0, load));
        sum += load;
      }
      const average = sum / current.length;
      root.value = Math.floor(average + 0.5) + "%";
    }

    root.previous = current;
  }

  Process {
    id: reader
    command: ["cat", "/proc/stat"]
    stdout: StdioCollector {
      id: reader_out
      onStreamFinished: root.update(reader_out.text)
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!reader.running) reader.running = true
  }

  PolyText {
    id: text
    theme: root.theme
    fonts: root.fonts
    segments: [
      { text: "\ue026 ", color: root.theme.foreground_alt },
      { text: root.value, color: root.theme.foreground }
    ]
  }
}
