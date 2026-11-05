import QtQuick

// One conky text run, placed by its baseline (conky draws with a baseline
// cursor and advances by Xft's per-glyph rounded widths).
Text {
  id: root

  required property var theme
  required property var fonts
  required property int font_index

  property real text_baseline: 0
  property string value: ""

  x: 0
  y: root.fonts.text_y(root.font_index, root.text_baseline)
  text: root.value
  color: {
    const c = root.text_color;
    if (root.font_index === 0)
      return Qt.rgba(c.r, c.g, c.b, root.theme.text_alpha);
    return c;
  }
  property color text_color: root.theme.default_color

  renderType: Text.NativeRendering
  textFormat: Text.PlainText
  wrapMode: Text.NoWrap
  clip: false

  font.family: root.fonts.family(root.font_index)
  font.pixelSize: root.fonts.qt_px(root.font_index)
  font.hintingPreference: Font.PreferVerticalHinting
  font.kerning: false
  font.letterSpacing: root.fonts.letter_spacing(root.font_index, root.value)
}
