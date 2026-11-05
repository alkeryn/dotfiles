import QtQuick

// Lays out a sequence of styled text segments with polybar's exact advances,
// font fallback and baseline placement.
Item {
  id: root

  required property var theme
  required property var fonts

  // [{ text, color, font?, bg? }]
  property var segments: []
  property int preferred_font: -1

  readonly property var layout_data: {
    // dependencies
    const rev = fonts.revision;
    const is_ready = fonts.ready;
    return is_ready ? fonts.expand(segments, preferred_font) : { runs: [], width: 0 };
  }

  implicitWidth: layout_data.width
  implicitHeight: theme.bar_height
  width: implicitWidth
  height: implicitHeight

  Repeater {
    model: root.layout_data.runs

    delegate: Text {
      required property var modelData

      x: modelData.x
      y: modelData.y
      text: modelData.text
      color: modelData.color

      // Qt's CFF stem darkening makes the CJK fallback bold when it goes
      // through the native rasteriser, so render that run unhinted instead.
      readonly property bool fallback: modelData.f === root.fonts.fallback_index

      renderType: fallback ? Text.QtRendering : Text.NativeRendering
      textFormat: Text.PlainText
      wrapMode: Text.NoWrap
      clip: false

      font.family: root.fonts.family(modelData.f)
      font.pixelSize: root.fonts.pixel_size(modelData.f)
      font.hintingPreference: fallback ? Font.PreferNoHinting : Font.PreferFullHinting
      font.kerning: false

      // polybar draws the text background over the whole bar height
      Rectangle {
        z: -1
        visible: modelData.bg !== ""
        x: 0
        y: -parent.y
        width: modelData.adv
        height: root.theme.bar_height
        color: modelData.bg
      }
    }
  }
}
