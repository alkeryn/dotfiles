import QtQuick
import Quickshell
import Quickshell.Io

// Resolves conky's Xft font names the same way Xft does (fontconfig), and
// exposes the metrics conky uses:
//   - ascent/descent are Xft's ceil()ed FreeType metrics at the *fractional*
//     pixel size (8pt at 120dpi = 13.333px -> ascent 15, descent 4)
//   - glyph advances are rounded per glyph, like Xft's integer positioning
Item {
  id: root

  required property var theme
  property bool active: true
  property bool ready: false
  property int revision: 0

  property var families: []
  property var char_cache: [{}, {}, {}, {}]

  FontMetrics {
    id: metrics0
    font.family: root.family(0)
    font.pixelSize: root.qt_px(0)
    font.hintingPreference: Font.PreferVerticalHinting
    font.kerning: false
  }
  FontMetrics {
    id: metrics1
    font.family: root.family(1)
    font.pixelSize: root.qt_px(1)
    font.hintingPreference: Font.PreferVerticalHinting
    font.kerning: false
  }
  FontMetrics {
    id: metrics2
    font.family: root.family(2)
    font.pixelSize: root.qt_px(2)
    font.hintingPreference: Font.PreferVerticalHinting
    font.kerning: false
  }
  FontMetrics {
    id: metrics3
    font.family: root.family(3)
    font.pixelSize: root.qt_px(3)
    font.hintingPreference: Font.PreferVerticalHinting
    font.kerning: false
  }

  function fm(index) {
    if (index === 1) return metrics1;
    if (index === 2) return metrics2;
    if (index === 3) return metrics3;
    return metrics0;
  }

  function family(index) {
    if (index < families.length && families[index]) return families[index];
    return index === 0 ? "monospace" : "DejaVu Sans";
  }

  // Qt only renders integral pixel sizes; conky's target is fractional.
  function qt_px(index) {
    return Math.max(1, Math.round(theme.font_px(index)));
  }

  // Xft: ascent = ceil(scaled ascender), descent = ceil(scaled descender).
  // Qt reports the same ratio at its (rounded) pixel size, so rescale.
  function ascent(index) {
    const px = qt_px(index);
    return Math.ceil(fm(index).ascent / px * theme.font_px(index) - 1e-6);
  }

  function descent(index) {
    const px = qt_px(index);
    return Math.ceil(fm(index).descent / px * theme.font_px(index) - 1e-6);
  }

  // conky's font_height() is ascent + descent
  function font_height(index) {
    return ascent(index) + descent(index);
  }

  // XftTextExtents xOff: every glyph advance is rounded to whole pixels.
  function advance(index, text) {
    const rev = revision; // dependency
    const cache = char_cache[index];
    let width = 0;
    for (const ch of Array.from(text)) {
      let adv = cache[ch];
      if (adv === undefined) {
        adv = Math.round(fm(index).advanceWidth(ch));
        cache[ch] = adv;
      }
      width += adv;
    }
    return width;
  }

  // Qt's unhinted advance for the same run (used to correct letter spacing).
  function natural_advance(index, text) {
    return fm(index).advanceWidth(text);
  }

  // Baseline -> QML Text y (the layout's top is y + FontMetrics.ascent).
  function text_y(index, baseline) {
    return baseline - fm(index).ascent;
  }

  // letterSpacing that makes Qt advance each character by conky's rounded
  // advance (exact for the monospace default font).
  function letter_spacing(index, text) {
    const chars = Array.from(text).length;
    if (chars === 0) return 0;
    return (advance(index, text) - natural_advance(index, text)) / chars;
  }

  onActiveChanged: if (active) reload.restart()
  onThemeChanged: reload.restart()

  // Xft.dpi may be discovered asynchronously; the font metrics change with it.
  Connections {
    target: root.theme
    function onDpiChanged() {
      root.char_cache = [{}, {}, {}, {}];
      root.revision += 1;
    }
  }

  Timer {
    id: reload
    interval: 50
    repeat: false
    onTriggered: {
      root.ready = false;
      root.families = [];
      root.char_cache = [{}, {}, {}, {}];
      if (root.active) match.running = true;
    }
  }

  Process {
    id: match
    running: root.active
    command: [
      "sh", "-c",
      "for f in 'Ubuntu Mono:size=8' 'Conky Icons by Carelli:size=14' " +
      "'Conky Icons by Carelli:size=30' 'Conky Icons by Carelli:size=9'; do " +
      "fc-match -f '%{family}\\n' \"$f\"; done"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        const text = this.text;
        const lines = text.split("\n").filter(function(l) { return l.trim().length > 0; });
        root.families = lines;
        Qt.callLater(function() {
          root.revision += 1;
          root.ready = true;
        });
      }
    }
  }
}
