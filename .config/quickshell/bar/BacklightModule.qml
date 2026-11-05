import QtQuick
import Quickshell
import Quickshell.Io

// [module/backlight] (laptop bar)
// card = amdgpu_bl1, format = <label> <ramp>, label = %percentage%%
Item {
  id: root

  required property var theme
  required property var fonts

  implicitHeight: theme.bar_height
  width: content.implicitWidth
  implicitWidth: width

  property bool available: false
  property string card: ""
  property double brightness: 0
  property double max_brightness: 0
  property int percentage: 0

  function update(raw) {
    const out = raw.trim();
    if (!out) {
      root.available = false;
      return;
    }
    const parts = out.split("|");
    if (parts.length < 3) {
      root.available = false;
      return;
    }
    root.card = parts[0];
    root.brightness = parseFloat(parts[1]) || 0;
    root.max_brightness = parseFloat(parts[2]) || 0;
    if (root.max_brightness <= 0) {
      root.available = false;
      return;
    }
    root.percentage = Math.min(100, Math.max(0, Math.round(100 * root.brightness / root.max_brightness)));
    root.available = true;
  }

  readonly property string ramp: {
    const icons = ["\u{1f315}", "\u{1f314}", "\u{1f313}", "\u{1f312}", "\u{1f311}"];
    let index = Math.trunc(percentage * icons.length / 100);
    index = Math.min(icons.length - 1, Math.max(0, index));
    return icons[index];
  }

  function change_brightness(delta) {
    if (root.card === "" || root.max_brightness <= 0) return;
    const next = Math.min(100, Math.max(0, root.percentage + delta));
    const value = Math.min(root.max_brightness, Math.max(0, Math.round(next * root.max_brightness / 100)));
    Quickshell.execDetached(["sh", "-c", "printf '%s' " + value + " > " + root.card + "/brightness"]);
  }

  Process {
    id: reader
    command: [
      "sh", "-c",
      "card=/sys/class/backlight/amdgpu_bl1; " +
      "[ -d \"$card\" ] || exit 1; " +
      "val=$(cat \"$card/actual_brightness\" 2>/dev/null); [ -n \"$val\" ] || val=$(cat \"$card/brightness\" 2>/dev/null); " +
      "max=$(cat \"$card/max_brightness\" 2>/dev/null); " +
      "printf '%s|%s|%s' \"$card\" \"$val\" \"$max\""
    ]
    stdout: StdioCollector {
      id: reader_out
      onStreamFinished: root.update(reader_out.text)
    }
  }

  Timer {
    interval: 1000
    running: root.theme.laptop
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
      segments: [{ text: root.percentage + "%", color: root.theme.foreground }]
    }

    Item { width: root.fonts.advance(0, " "); height: root.theme.bar_height }

    PolyText {
      theme: root.theme
      fonts: root.fonts
      segments: [{ text: root.ramp, color: root.theme.foreground }]
    }
  }

  WheelHandler {
    onWheel: function(event) {
      if (event.angleDelta.y > 0) root.change_brightness(5);
      else if (event.angleDelta.y < 0) root.change_brightness(-5);
    }
  }
}
