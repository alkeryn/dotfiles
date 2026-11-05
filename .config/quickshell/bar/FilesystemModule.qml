import QtQuick
import Quickshell.Io

// [module/filesystem]
// mount-0 = /home
// mounted:   %{F#0a81f5}/home%{F-}: <used>%
// unmounted: /home not mounted   (foreground-alt)
Item {
  id: root

  required property var theme
  required property var fonts

  implicitHeight: theme.bar_height
  width: text.implicitWidth
  implicitWidth: width

  property string mount: "/home"
  property bool mounted: false
  property int used_percent: 0

  function shell_quote(value) {
    return "'" + ("" + value).replace(/'/g, "'\\''") + "'";
  }

  function update(raw) {
    const out = raw.trim();
    if (!out || out === "NOMOUNT") {
      root.mounted = false;
      return;
    }
    const parts = out.split(/\s+/);
    if (parts.length < 4) {
      root.mounted = false;
      return;
    }
    const block_size = parseFloat(parts[0]);
    const blocks = parseFloat(parts[1]);
    const blocks_free = parseFloat(parts[2]);
    const blocks_avail = parseFloat(parts[3]);
    const total = block_size * blocks;
    const free = block_size * blocks_free;
    const used = total - free;
    const avail = block_size * blocks_avail;
    const denominator = used + avail;
    root.used_percent = denominator > 0
      ? Math.min(100, Math.max(0, Math.round(100 * used / denominator)))
      : 0;
    root.mounted = true;
  }

  Process {
    id: reader
    command: [
      "sh", "-c",
      "m=" + root.shell_quote(root.mount) + "; " +
      "if awk -v m=\"$m\" '$5==m{f=1} END{exit !f}' /proc/self/mountinfo 2>/dev/null; then " +
      "stat -f -c '%S %b %f %a' \"$m\"; else echo NOMOUNT; fi"
    ]
    stdout: StdioCollector {
      id: reader_out
      onStreamFinished: root.update(reader_out.text)
    }
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!reader.running) reader.running = true
  }

  PolyText {
    id: text
    theme: root.theme
    fonts: root.fonts
    segments: root.mounted
      ? [
          { text: root.mount, color: root.theme.fs_mount },
          { text: ": " + root.used_percent + "%", color: root.theme.foreground }
        ]
      : [
          { text: root.mount + " not mounted", color: root.theme.foreground_alt }
        ]
  }
}
