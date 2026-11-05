import QtQuick

// A conky ${hr h} rule.  Conky draws a line of thickness h centred on
// cur_y - font_ascent()/4, from the text origin to the right edge of the
// text area (thick lines cover [y - h/2, y + h/2)).
Rectangle {
  id: root

  required property color hr_color
  property real line_x: 0
  property real line_center_y: 0
  property int line_width: 0
  property int line_height: 1

  x: root.line_x
  y: root.line_center_y - Math.floor(root.line_height / 2)
  width: root.line_width
  height: root.line_height
  color: root.hr_color
  antialiasing: false
}
