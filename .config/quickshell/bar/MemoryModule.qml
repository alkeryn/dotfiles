import QtQuick
import Quickshell.Io

// [module/memory]
// format-prefix = <siji E028>, label = %percentage_used%%
Item {
  id: root

  required property var theme
  required property var fonts

  implicitHeight: theme.bar_height
  width: text.implicitWidth
  implicitWidth: width

  property string value: "0%"

  function update(raw) {
    let total = 0;
    let available = 0;
    let free = 0;
    let buffers = 0;
    let cached = 0;
    let reclaimable = 0;
    let shmem = 0;
    let have_available = false;

    const lines = raw.split("\n");
    for (let i = 0; i < lines.length; ++i) {
      const m = lines[i].match(/^([A-Za-z_()]+):\s+(\d+)/);
      if (!m) continue;
      const key = m[1];
      const val = parseInt(m[2], 10);
      if (key === "MemTotal") total = val;
      else if (key === "MemAvailable") { available = val; have_available = true; }
      else if (key === "MemFree") free = val;
      else if (key === "Buffers") buffers = val;
      else if (key === "Cached") cached = val;
      else if (key === "SReclaimable") reclaimable = val;
      else if (key === "Shmem") shmem = val;
    }
    if (!have_available) available = free + buffers + cached + reclaimable - shmem;
    if (total <= 0) return;

    const free_pct = Math.min(100, Math.max(0, Math.round(100 * available / total)));
    root.value = (100 - free_pct) + "%";
  }

  Process {
    id: reader
    command: ["cat", "/proc/meminfo"]
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
      { text: "\ue028 ", color: root.theme.foreground_alt },
      { text: root.value, color: root.theme.foreground }
    ]
  }
}
