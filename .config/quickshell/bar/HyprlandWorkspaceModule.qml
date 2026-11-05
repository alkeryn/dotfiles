import QtQuick
import Quickshell.Hyprland

// [module/workspaces]
// The original tag styling is reused: 2 spaces of padding, focused =
// background-alt, urgent = alert, empty = foreground-alt, occupied = foreground.
Item {
  id: root

  required property var theme
  required property var fonts

  implicitHeight: theme.bar_height
  readonly property real tags_width: {
    // Force a dependency on font loading, which also invalidates pad.
    const rev = fonts.revision;
    const ready = fonts.ready;
    let total = 0;
    if (ready) {
      for (let i = 0; i < workspaces.length; ++i) {
        const w = workspaces[i];
        const text = label(w) + ((w.urgent && !w.focused) ? "!" : "");
        total += pad * 2 + fonts.advance(0, text);
      }
    }
    return total;
  }
  width: tags_width
  implicitWidth: tags_width

  readonly property real pad: fonts.ready ? fonts.advance(0, "  ") : 0

  // The original bar always showed all ten desktops, including empty ones.
  // Hyprland only reports workspaces that exist, so
  // merge its list with placeholders for 1..workspace_count.  This also makes
  // the tag strip visible when the Hyprland IPC is temporarily unavailable.
  readonly property int workspace_count: 10

  readonly property var workspaces: {
    const all = Hyprland.workspaces.values || [];
    const by_name = {};
    for (let i = 0; i < all.length; ++i) {
      const w = all[i];
      if (!w) continue;
      const name = (w.name === undefined || w.name === null) ? "" : "" + w.name;
      if (name !== "") by_name[name] = w;
    }

    const out = [];
    for (let id = 1; id <= root.workspace_count; ++id) {
      const name = "" + id;
      const real = by_name[name];
      if (real) {
        out.push(real);
      } else {
        out.push({
          id: id,
          name: name,
          focused: false,
          urgent: false,
          is_placeholder: true,
          toplevels: null,
          activate: function() { Hyprland.dispatch("workspace " + name); }
        });
      }
    }

    // Named or high-numbered workspaces still get a tag, after the fixed row.
    for (let i = 0; i < all.length; ++i) {
      const w = all[i];
      if (!w) continue;
      const name = (w.name === undefined || w.name === null) ? "" : "" + w.name;
      if (name === "") continue;
      const numeric = /^[0-9]+$/.test(name);
      const in_fixed_range = numeric && Number(name) >= 1 && Number(name) <= root.workspace_count;
      if (!in_fixed_range) out.push(w);
    }

    return out;
  }

  readonly property bool has_content: true


  function label(w) {
    const name = (w.name === undefined || w.name === null) ? "" : "" + w.name;
    if (/^[0-9]+$/.test(name)) return name;
    return name !== "" ? name : "" + w.id;
  }

  function occupied(w) {
    if (!w || w.is_placeholder) return false;
    return w.toplevels && w.toplevels.values ? w.toplevels.values.length > 0 : false;
  }

  Row {
    id: content
    width: root.tags_width
    height: root.theme.bar_height
    spacing: 0

    Repeater {
      model: root.workspaces

      delegate: Item {
        required property var modelData

        readonly property bool focused: modelData.focused
        readonly property bool urgent: modelData.urgent
        readonly property bool is_occupied: root.occupied(modelData)
        readonly property string label_text: root.label(modelData) + ((urgent && !focused) ? "!" : "")
        readonly property color label_color: (!focused && !urgent && !is_occupied)
          ? root.theme.foreground_alt
          : root.theme.foreground
        readonly property color label_bg: focused
          ? root.theme.background_alt
          : (urgent ? root.theme.alert : "transparent")

        width: root.pad * 2 + root.fonts.advance(0, label_text)
        height: root.theme.bar_height

        Rectangle {
          anchors.fill: parent
          color: parent.label_bg
          visible: parent.label_bg != "transparent"
        }

        PolyText {
          x: root.pad
          theme: root.theme
          fonts: root.fonts
          segments: [{ text: parent.label_text, color: parent.label_color }]
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton
          onClicked: modelData.activate()
        }
      }
    }
  }

  WheelHandler {
    onWheel: function(event) {
      if (event.angleDelta.y > 0) Hyprland.dispatch("workspace e-1");
      else if (event.angleDelta.y < 0) Hyprland.dispatch("workspace e+1");
    }
  }
}
