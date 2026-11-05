import QtQuick
import Quickshell
import Quickshell.Io

// Reproduces polybar's font handling:
//  - the three fonts from the bar config are a fallback chain
//  - a fontconfig-selected Japanese font is appended to the chain, so CJK
//    text (window titles, mpd tags) is rendered instead of dropped
//  - the effective pixel size is computed the same way polybar's font_fc::size()
//    does (fontconfig FC_SIZE + bar DPI of 96)
//  - glyphs not present in any font of the chain are dropped (zero width)
//  - each font's baseline is the one polybar's cairo text renderer uses
Item {
  id: root

  property int bar_height: 27
  property bool laptop: false
  property bool active: true
  property bool ready: false
  property int revision: 0

  // [{ family, px, ranges: [[lo, hi], ...], baseline }]
  property var fonts: []

  // FontMetrics objects are kept as separate children so QML can use their
  // hinted advances and ascents synchronously.
  FontMetrics {
    id: metrics0
    font.family: root.family(0)
    font.pixelSize: root.pixel_size(0)
    font.hintingPreference: Font.PreferFullHinting
    font.kerning: false
  }
  FontMetrics {
    id: metrics1
    font.family: root.family(1)
    font.pixelSize: root.pixel_size(1)
    font.hintingPreference: Font.PreferFullHinting
    font.kerning: false
  }
  FontMetrics {
    id: metrics2
    font.family: root.family(2)
    font.pixelSize: root.pixel_size(2)
    font.hintingPreference: Font.PreferFullHinting
    font.kerning: false
  }
  FontMetrics {
    id: metrics3
    font.family: root.family(3)
    font.pixelSize: root.pixel_size(3)
    // Qt re-enables FreeType's CFF stem darkening, which makes Noto CJK look
    // bold at bar sizes.  Leave the fallback unhinted so it stays light.
    font.hintingPreference: Font.PreferNoHinting
    font.kerning: false
  }

  // Index of the appended CJK fallback in `fonts` (-1 when absent).
  readonly property int fallback_index: fonts.length > 3 ? 3 : -1

  function family(i) {
    if (i < fonts.length && fonts[i].family) return fonts[i].family;
    if (i === 1) return "Siji";
    if (i === 2) return "FontAwesome";
    if (i === 3) return "Noto Sans CJK JP DemiLight";
    return "DejaVu Sans";
  }

  function pixel_size(i) {
    if (i < fonts.length) return fonts[i].px;
    if (i === 1) return 10;
    if (i === 2) return 18;
    if (i === 3) return laptop ? 20 : 13;
    return 13;
  }

  function metrics(i) {
    if (i === 1) return metrics1;
    if (i === 2) return metrics2;
    if (i === 3) return metrics3;
    return metrics0;
  }

  function ascent(i) {
    return metrics(i).ascent;
  }

  function advance(i, text) {
    const rev = revision;
    return Math.ceil(metrics(i).advanceWidth(text));
  }

  function covers(i, cp) {
    if (i < 0 || i >= fonts.length) return false;
    const ranges = fonts[i].ranges;
    let lo = 0;
    let hi = ranges.length - 1;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      const r = ranges[mid];
      if (cp < r[0]) hi = mid - 1;
      else if (cp > r[1]) lo = mid + 1;
      else return true;
    }
    return false;
  }

  // Font indices in polybar's fallback order for a given preferred font.
  function font_order(preferred) {
    const order = [];
    for (let i = 0; i < fonts.length; ++i) order.push(i);
    if (preferred > 0 && preferred < order.length) {
      const tmp = order[0];
      order[0] = order[preferred];
      order[preferred] = tmp;
    }
    return order;
  }

  function font_for(cp, preferred) {
    const order = font_order(preferred === undefined ? -1 : preferred);
    for (let i = 0; i < order.length; ++i) {
      if (covers(order[i], cp)) return order[i];
    }
    return -1;
  }

  // Segments are { text, color, font?, bg? }.  Returns runs with x/adv/y.
  function expand(segments, preferred) {
    const runs = [];
    if (!ready) return { runs: runs, width: 0 };

    for (let s = 0; s < segments.length; ++s) {
      const seg = segments[s];
      if (!seg || seg.text === undefined || seg.text === null) continue;
      const preferred_font = seg.font !== undefined ? seg.font : (preferred !== undefined ? preferred : -1);
      const color = seg.color !== undefined ? seg.color : "#dfdfdf";
      const bg = seg.bg !== undefined ? seg.bg : "";
      const text = "" + seg.text;
      let run = null;

      for (const ch of Array.from(text)) {
        const cp = ch.codePointAt(0);
        const fi = font_for(cp, preferred_font);
        if (fi < 0) {
          // polybar drops characters no configured font can render
          run = null;
          continue;
        }
        if (!run || run.f !== fi || run.color !== color || run.bg !== bg) {
          run = { f: fi, text: "", color: color, bg: bg };
          runs.push(run);
        }
        run.text += ch;
      }
    }

    let pos = 0;
    for (let i = 0; i < runs.length; ++i) {
      const r = runs[i];
      r.adv = advance(r.f, r.text);
      r.x = pos;
      r.y = root.y_offset(r.f);
      pos += r.adv;
    }
    return { runs: runs, width: pos };
  }

  // cairo font extents as seen by polybar for the fonts in this config.
  function cairo_metrics(family_name, px) {
    if (family_name.indexOf("DejaVu Sans") === 0) {
      if (px === 13) return { asc: 13, desc: 4, height: 15 };
      if (px === 20) return { asc: 19, desc: 5, height: 23 };
      return { asc: Math.round(px), desc: Math.round(px * 4 / 13), height: Math.round(px * 15 / 13) };
    }
    if (family_name === "Siji") {
      return { asc: 8, desc: 2, height: 10 };
    }
    const lower = family_name.toLowerCase();
    if (lower.indexOf("awesome") >= 0) {
      return { asc: Math.round(px * 0.89), desc: Math.round(px * 0.17), height: px };
    }
    // fontconfig's fallback for the missing FontAwesome is a scalable sans;
    // measured at 18px as 20/6/25.
    return { asc: Math.round(px * 20 / 18), desc: Math.round(px * 6 / 18), height: Math.round(px * 25 / 18) };
  }

  function font_baseline(i) {
    if (i >= fonts.length) return 0;
    return fonts[i].baseline;
  }

  function y_offset(i) {
    const rev = revision;
    return font_baseline(i) - ascent(i);
  }

  function parse_ranges(spec) {
    const ranges = [];
    const tokens = spec.trim().split(/\s+/);
    for (let i = 0; i < tokens.length; ++i) {
      const tok = tokens[i];
      if (!tok) continue;
      const dash = tok.indexOf("-");
      let lo, hi;
      if (dash < 0) {
        lo = parseInt(tok, 16);
        hi = lo;
      } else {
        lo = parseInt(tok.substring(0, dash), 16);
        hi = parseInt(tok.substring(dash + 1), 16);
      }
      if (!isNaN(lo) && !isNaN(hi)) ranges.push([lo, hi]);
    }
    ranges.sort(function(a, b) { return a[0] - b[0]; });
    return ranges;
  }

  function effective_px(pixelsize, size, scalable) {
    const pxs = parseFloat(pixelsize) || 0;
    const sz = parseFloat(size) || 0;
    const scal = ("" + scalable).toLowerCase() === "true";
    if (pxs === 0 && sz === 0) {
      return scal ? Math.trunc(10 / 72 * 96 + 0.5) : Math.trunc(10 + 0.5);
    } else if (scal) {
      return sz !== 0 ? Math.trunc(sz / 72 * 96 + 0.5) : Math.trunc(pxs + 0.5);
    }
    return pxs !== 0 ? Math.trunc(pxs + 0.5) : Math.trunc(sz / 72 * 96 + 0.5);
  }

  function parse_font(line, offset, baseline, use_fullname) {
    const fields = line.split("|");
    if (fields.length < 5) return null;
    let family = fields[0].split(",")[0];
    // The full name carries the weight/style (e.g. "... DemiLight"), which a
    // plain family name would drop, making Qt pick the Regular face again.
    if (use_fullname && fields.length >= 6 && fields[5])
      family = fields[5].split(",")[0];
    if (!family) return null;
    const px = effective_px(fields[1], fields[2], fields[3]);
    const m = cairo_metrics(family, px);
    const base = baseline !== undefined
      ? baseline
      : bar_height / 2 - (m.desc / 2 - m.height / 4) + offset;
    return {
      family: family,
      px: px,
      ranges: parse_ranges(fields[4]),
      baseline: base
    };
  }

  function rebuild() {
    const parsed = [];
    for (let i = 0; i < raw.length; ++i) {
      const font = parse_font(raw[i], i < 2 ? 1 : 0);
      if (font) parsed.push(font);
    }
    if (parsed.length === 0) return;
    // CJK fallback: keep the primary font's baseline so Latin and Japanese
    // text in the same label line up.  Qt enables FreeType CFF stem
    // darkening, so the Regular Noto CJK face looks bold at bar sizes.  Ask
    // fontconfig for its DemiLight Japanese face and select it by full name;
    // that matches the weight Pango/waybar shows for regular CJK text.
    const cjk = parse_font(fallback_raw, 0, parsed[0].baseline, true);
    if (cjk) parsed.push(cjk);
    fonts = parsed;
    // Wait for the FontMetrics bindings to pick up the new fonts before the
    // first layout pass reads their ascent.
    Qt.callLater(function() {
      revision += 1;
      ready = true;
    });
  }

  property var raw: []
  property var fallback_raw: ""

  onBar_heightChanged: {
    if (raw.length > 0) rebuild();
  }

  // The profile (and therefore the configured font sizes) can be discovered
  // asynchronously.  If that happens while the font match is already loading,
  // restart it with the correct font patterns.
  onLaptopChanged: {
    if (match_process.running) match_process.running = false;
    raw = [];
    fallback_raw = "";
    fonts = [];
    ready = false;
    if (active) reload_timer.restart();
  }

  Timer {
    id: reload_timer
    interval: 100
    repeat: false
    onTriggered: match_process.running = true
  }

  Process {
    id: match_process
    running: root.active
    command: [
      "sh", "-c",
      "for f in '" + (root.laptop ? "DejaVuSans:pixelsize=16" : "DejaVuSans:pixelsize=10") + "' 'Siji:pixelsize=10' 'FontAwesome:pixelsize=14'; do " +
      "fc-match -f '%{family}|%{pixelsize}|%{size}|%{scalable}|%{charset}|%{fullname}\\n' \"$f\"; done; " +
      "fc-match -f '%{family}|%{pixelsize}|%{size}|%{scalable}|%{charset}|%{fullname}\\n' " +
      "':lang=ja:weight=demilight:pixelsize=" + (root.laptop ? "16" : "10") + "'"
    ]
    stdout: StdioCollector {
      id: match_out
      onStreamFinished: {
        const text = match_out.text;
        const lines = text.split("\n").filter(function(l) { return l.trim().length > 0; });
        root.raw = lines.slice(0, 3);
        root.fallback_raw = lines.length > 3 ? lines[3] : "";
        root.rebuild();
      }
    }
  }
}
