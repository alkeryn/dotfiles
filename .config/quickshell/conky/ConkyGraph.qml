import QtQuick

// A conky graph: one 1px column per sample, newest at the right edge
// (draw_graph_bars() in conky.cc).  Zero-valued samples draw nothing.
Item {
  id: root

  required property color graph_color
  property int graph_x: 0
  property int graph_y: 0
  property int graph_width: 0
  property int graph_height: 0
  property var graph_data: []
  property real graph_scale: 1

  x: root.graph_x
  y: root.graph_y
  width: root.graph_width
  height: root.graph_height

  Repeater {
    model: Math.max(0, root.graph_width - 1)

    delegate: Rectangle {
      required property int index
      readonly property real sample: index < root.graph_data.length ? root.graph_data[index] : 0
      readonly property int pixels: {
        if (root.graph_scale <= 0) return 0;
        return Math.round(sample * (root.graph_height - 1) / root.graph_scale);
      }

      visible: pixels > 0
      x: root.graph_width - 1 - index
      y: root.graph_height - pixels
      width: 1
      height: pixels
      color: root.graph_color
      antialiasing: false
    }
  }
}
