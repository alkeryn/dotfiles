import QtQuick

// Geometry and appearance of the conky "desktop" window, mirroring
// ~/.config/conky/conky.conf.
//
// Conky draws in physical pixels but scales every "layout" value by
// Xft.dpi / 96 (dpi_scale() in conky's display-output.hh), while font sizes
// are point sizes resolved by Xft at the same DPI.  The port does the same.
QtObject {
  id: theme

  // Xft.dpi as seen by conky (see ConkyDpi) - 120 on mainpc
  property int dpi: 120

  // window placement / text area, straight from conky.conf.  Its
  // minimum_height is not used: the port's rows are dynamic, so the window
  // hugs the content instead of keeping an empty band at the bottom.
  readonly property int minimum_width: 370
  readonly property int border_inner_margin: 25
  readonly property int border_outer_margin: 0
  readonly property int border_width: 1
  readonly property int gap_x: 45
  readonly property int gap_y: 45

  // own_window_colour = '#78000000'
  readonly property color background: "#78000000"

  // default_color = '#FFFFFF'
  readonly property color default_color: "#ffffff"

  // xftalpha = 0.8 (text_alpha), applied to font 0 only by conky
  readonly property real text_alpha: 0.8

  // fonts in conky.font order; index 0 is the `${font}` default
  readonly property var font_specs: [
    { pattern: "Ubuntu Mono:size=8", size: 8 },
    { pattern: "Conky Icons by Carelli:size=14", size: 14 },
    { pattern: "Conky Icons by Carelli:size=30", size: 30 },
    { pattern: "Conky Icons by Carelli:size=9", size: 9 }
  ]

  // graph colours from the config
  readonly property color graph_read_color: "#2216e1"
  readonly property color graph_write_color: "#dd3a21"

  readonly property real px_scale: dpi / 96

  // conky's dpi_scale(): round(value * dpi / 96)
  function dpi_scale(value) {
    return Math.round(value * px_scale);
  }

  // conky/Xft pixel size: point size * dpi / 72
  function font_px(index) {
    const spec = font_specs[index];
    return spec ? spec.size * dpi / 72 : 0;
  }

  // get_border_total(): inner + outer + border_width, each scaled
  function border_total() {
    return dpi_scale(border_inner_margin)
      + dpi_scale(border_outer_margin)
      + dpi_scale(border_width);
  }
}
