import QtQuick
import Quickshell.Services.Pipewire

// [module/volume] (internal/alsa, fed by the default PipeWire sink)
// format-volume = <label-volume> <bar-volume>
// label-volume = VOL
// format-muted-prefix = <siji E202 + space>, format-muted-foreground = alt
// label-muted = sound muted
// bar-volume-width = 10, fill/empty font = 2
Item {
  id: root

  required property var theme
  required property var fonts

  implicitHeight: theme.bar_height
  width: content.implicitWidth
  implicitWidth: width

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var audio: sink ? sink.audio : null

  // PwNodeAudio's volume/muted properties are only valid while the node is
  // bound through a PwObjectTracker.  Without this, audio.volume is 0 and
  // setting it is a no-op.
  PwObjectTracker {
    objects: root.sink ? [root.sink] : []
  }

  readonly property bool available: Pipewire.ready && sink !== null && sink.ready
    && audio !== null && audio.volumes.length > 0
  readonly property bool muted: audio ? audio.muted : false
  readonly property int volume_percent: audio
    ? Math.min(100, Math.max(0, Math.round(audio.volume * 100)))
    : 0

  readonly property int fill_count: Math.min(9, Math.max(0, Math.round(volume_percent * 9 / 100)))
  readonly property int empty_count: 9 - fill_count
  readonly property color fill_color: {
    const colors = [
      "#55aa55", "#55aa55", "#55aa55", "#55aa55", "#55aa55",
      "#f5a70a", "#ff5555"
    ];
    const i = Math.min(6, Math.max(0, Math.round(volume_percent * 6 / 100)));
    return colors[i];
  }

  readonly property var bar_segments: [
    { text: "\u2500".repeat(fill_count), color: fill_color },
    { text: "|", color: theme.foreground },
    { text: "\u2500".repeat(empty_count), color: theme.foreground_alt }
  ]

  // One wheel notch is 120 units.  Accumulate them instead of applying a
  // step per event: high-resolution wheels/touchpads send many small deltas
  // and used to jump the volume by 5% for every one of them.
  property real wheel_accum: 0
  readonly property int volume_step: 2

  function scroll_volume(delta) {
    if (!audio) return;
    root.wheel_accum += delta;
    if (Math.abs(root.wheel_accum) < 120) return;
    const steps = Math.trunc(root.wheel_accum / 120);
    root.wheel_accum -= steps * 120;
    const value = Math.min(100, Math.max(0, volume_percent + steps * root.volume_step));
    audio.volume = value / 100;
  }

  Row {
    id: content
    spacing: 0

    PolyText {
      visible: !root.muted
      theme: root.theme
      fonts: root.fonts
      segments: [{ text: "VOL", color: root.theme.foreground }]
    }

    Item {
      visible: !root.muted
      width: visible ? root.fonts.advance(0, " ") : 0
      height: root.theme.bar_height
    }

    PolyText {
      visible: !root.muted
      theme: root.theme
      fonts: root.fonts
      preferred_font: 2
      segments: root.bar_segments
    }

    PolyText {
      visible: root.muted
      theme: root.theme
      fonts: root.fonts
      segments: [
        { text: "\ue202 ", color: root.theme.foreground_alt },
        { text: "sound muted", color: root.theme.foreground_alt }
      ]
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.available
    acceptedButtons: Qt.LeftButton
    onClicked: if (root.audio) root.audio.muted = !root.audio.muted
    onWheel: function(wheel) {
      if (wheel.angleDelta.y !== 0) root.scroll_volume(wheel.angleDelta.y);
    }
  }
}
