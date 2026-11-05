import QtQuick
import Quickshell.Io

// [module/battery] (laptop bar center)
// battery = BAT0, adapter = ADP1, poll-interval = 1
// time-format = %H:%M
// format-charging = <label-charging> <animation-charging>
// format-discharging = <label-discharging> <ramp-capacity>
// format-full = <label-full> <ramp-capacity>
Item {
  id: root

  required property var theme
  required property var fonts

  implicitHeight: theme.bar_height
  width: content.implicitWidth
  implicitWidth: width

  property bool available: false
  property string status_text: ""
  property int online: 0
  property double cap_now: 0
  property double cap_full: 0
  property double voltage: 0
  property double rate: 0
  property string rate_kind: ""

  property int percentage: 0
  property string state: "discharging"
  property double consumption: 0
  property int remaining_seconds: 0

  property int animation_frame: 4

  readonly property int low_at: 10
  readonly property int full_at: 100

  readonly property int shown_percentage: state === "full" && percentage >= full_at ? 100 : percentage

  function update(raw) {
    const out = raw.trim();
    if (!out) {
      root.available = false;
      return;
    }
    const parts = out.split("|");
    if (parts.length < 7) {
      root.available = false;
      return;
    }
    root.status_text = parts[0];
    root.online = parseInt(parts[1], 10) || 0;
    root.cap_now = parseFloat(parts[2]) || 0;
    root.cap_full = parseFloat(parts[3]) || 0;
    root.voltage = parseFloat(parts[4]) || 0;
    root.rate = parseFloat(parts[5]) || 0;
    root.rate_kind = parts[6];

    if (root.cap_full <= 0) {
      root.available = false;
      return;
    }

    root.percentage = Math.min(100, Math.max(0, Math.round(100 * root.cap_now / root.cap_full)));

    const charging = root.status_text.indexOf("Charging") === 0 || root.online === 1;
    if (root.percentage >= root.full_at) root.state = "full";
    else if (!charging) root.state = root.percentage <= root.low_at ? "low" : "discharging";
    else root.state = "charging";

    // polybar battery.cpp: consumption_reader
    if (root.rate_kind === "current") {
      root.consumption = ((root.voltage / 1000.0) * (root.rate / 1000.0)) / 1e6;
    } else {
      root.consumption = root.rate / 1e6;
    }

    // polybar battery.cpp: rate_reader -> current_time
    const volt = Math.trunc(root.voltage / 1000);
    const cap = charging ? root.cap_full - root.cap_now : root.cap_now;
    if (root.rate && volt && cap) {
      const remaining = Math.trunc(cap / volt);
      const current_rate = Math.trunc(root.rate / volt);
      root.remaining_seconds = (remaining && current_rate)
        ? Math.floor(3600 * remaining / current_rate)
        : 0;
    } else {
      root.remaining_seconds = 0;
    }

    root.available = true;
  }

  function time_string(seconds) {
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    return theme.pad2(hours) + ":" + theme.pad2(minutes);
  }

  readonly property string consumption_string: consumption.toFixed(2)
  readonly property string label_text: {
    if (state === "full") {
      return "%time% Fully charged@" + consumption_string + "W " + shown_percentage + "%";
    } else if (state === "charging") {
      return time_string(remaining_seconds) + " Charging@" + consumption_string + "W " + shown_percentage + "%";
    }
    return time_string(remaining_seconds) + " Discharging@" + consumption_string + "W " + shown_percentage + "%";
  }

  function ramp_icon(percent) {
    // ramp-capacity-0 .. ramp-capacity-4 = U+F244 .. U+F240
    const icons = ["\uf244", "\uf243", "\uf242", "\uf241", "\uf240"];
    let index;
    if (percent <= low_at) index = 0;
    else if (percent >= full_at) index = 4;
    else {
      const pct = Math.round((percent - low_at) / (full_at - low_at) * 100);
      index = Math.trunc(pct * (icons.length - 2) / 100 + 1);
      index = Math.min(icons.length - 1, Math.max(0, index));
    }
    return icons[index];
  }

  readonly property string icon_text: state === "charging"
    ? ["\uf244", "\uf243", "\uf242", "\uf241", "\uf240"][animation_frame]
    : ramp_icon(percentage)

  Process {
    id: reader
    command: [
      "sh", "-c",
      "base=/sys/class/power_supply/BAT0; [ -d \"$base\" ] || exit 1; " +
      "status=$(cat \"$base/status\" 2>/dev/null); " +
      "online=$(cat /sys/class/power_supply/ADP1/online 2>/dev/null); " +
      "now=$(cat \"$base/charge_now\" 2>/dev/null); [ -n \"$now\" ] || now=$(cat \"$base/energy_now\" 2>/dev/null); " +
      "full=$(cat \"$base/charge_full\" 2>/dev/null); [ -n \"$full\" ] || full=$(cat \"$base/energy_full\" 2>/dev/null); " +
      "volt=$(cat \"$base/voltage_now\" 2>/dev/null); " +
      "rate=$(cat \"$base/current_now\" 2>/dev/null); kind=current; " +
      "if [ -z \"$rate\" ]; then rate=$(cat \"$base/power_now\" 2>/dev/null); kind=power; fi; " +
      "printf '%s|%s|%s|%s|%s|%s|%s' \"$status\" \"$online\" \"$now\" \"$full\" \"$volt\" \"$rate\" \"$kind\""
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

  Timer {
    interval: 750
    running: root.available && root.state === "charging"
    repeat: true
    onTriggered: root.animation_frame = (root.animation_frame + 1) % 5
  }

  Row {
    id: content
    spacing: 0

    PolyText {
      theme: root.theme
      fonts: root.fonts
      segments: [{ text: root.label_text, color: root.theme.foreground }]
    }

    Item { width: root.fonts.advance(0, " "); height: root.theme.bar_height }

    PolyText {
      theme: root.theme
      fonts: root.fonts
      segments: [{ text: root.icon_text, color: root.theme.foreground }]
    }
  }
}
