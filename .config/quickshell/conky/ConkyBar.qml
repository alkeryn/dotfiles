import QtQuick

// A conky bar: XDrawRectangle(x, y, w, h) outline plus XFillRectangle of the
// used part (conky's outline spans w+1 x h+1 pixels).
Item {
  id: root

  required property color bar_color
  property int bar_x: 0
  property int bar_y: 0
  property int bar_width: 0
  property int bar_height: 0
  property int fill_width: 0

  x: root.bar_x
  y: root.bar_y
  width: root.bar_width + 1
  height: root.bar_height + 1

  Rectangle {
    x: 0
    y: 0
    width: root.bar_width + 1
    height: root.bar_height + 1
    color: "transparent"
    border.width: 1
    border.color: root.bar_color
    antialiasing: false
  }

  Rectangle {
    x: 0
    y: 0
    width: Math.max(0, Math.min(root.bar_width, root.fill_width))
    height: root.bar_height
    color: root.bar_color
    antialiasing: false
  }
}
