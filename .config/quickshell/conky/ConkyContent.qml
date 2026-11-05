import QtQuick

// Pixel-for-pixel reimplementation of ~/.config/conky/conky.conf.
//
// The geometry follows conky's own algorithms:
//   - Xft.dpi / 96 scaling for layout values (dpi_scale)
//   - text_size from a sizing pass that uses the previous frame's cursor
//   - line baselines advance by ascent/descent with voffset support
//   - ${goto} is an absolute pixel position inside the window
//   - bars/graphs use the same rectangle/line offsets as conky
Item {
  id: win

  property var theme: null
  property var fonts: null
  property var source: null

  readonly property int border: theme ? theme.border_total() : 0

  // conky's text area size, recomputed like update_text_area()
  property var frame: win.compute_frame()
  // cur_x / selected font of the previous frame, used by the sizing pass
  // (conky keeps both in static variables)
  property real stale_cur_x: 0
  property int prev_end_font: 0

  onFrameChanged: Qt.callLater(function() {
    if (win.stale_cur_x !== win.frame.end_x)
      win.stale_cur_x = win.frame.end_x;
    if (win.prev_end_font !== win.frame.end_font)
      win.prev_end_font = win.frame.end_font;
  })

  // ---- conky.conf ------------------------------------------------------
  function build_lines() {
    if (!source) return [];
    const rev = source.revision;
    const d = source;
    const white = "#ffffff";
    const cyan = "#00ffff";
    const fs = function(path) {
      const info = d.filesystems[path];
      return info ? info : { perc: 0, free: d.human_readable(0), frac: 0 };
    };
    const disk = function(dev) {
      const info = d.disks[dev];
      return info ? info : {
        read: d.human_readable(0), write: d.human_readable(0),
        read_hist: [], write_hist: []
      };
    };
    const top = function(i, field) {
      const row = d.top_rows[i];
      return row ? row[field] : 0;
    };
    const top_name = function(i) {
      let name = "" + top(i, "name");
      if (name.length < 16) name += " ".repeat(16 - name.length);
      return name + " ";
    };
    const top_pid = function(i) {
      return ("" + (top(i, "pid") | 0)).padStart(7, " ");
    };
    const top_cpu = function(i) {
      return d.fixed(top(i, "cpu"), 2).padStart(6, " ");
    };
    const top_mem = function(i) {
      return d.fixed(top(i, "mem"), 2).padStart(6, " ");
    };
    const graph_scale = function(values) {
      let max = 0;
      for (let i = 0; i < values.length; ++i)
        if (values[i] > max) max = values[i];
      return max < 1e-47 ? 1e-47 : max;
    };
    const all_disks = function() { return disk("total"); };
    const root_fs = fs("/");
    const home_fs = fs("/home/alkeryn");
    const back = "#ffffff";

    // Only the interfaces that exist and are connected are drawn: WLAN and
    // ETH keep their columns, a lone interface takes the first one.
    const net_columns = [];
    const ifaces = d.net_interfaces || [];
    for (let i = 0; i < ifaces.length; ++i) {
      const role = ifaces[i].role;
      if (role !== "wlan" && role !== "eth") continue;
      let taken = false;
      for (let c = 0; c < net_columns.length; ++c)
        if (net_columns[c].role === role) taken = true;
      if (taken) continue;
      net_columns.push({
        role: role,
        label: role === "wlan" ? "WLAN" : "ETH",
        dev: ifaces[i].dev,
        x: net_columns.length === 0 ? 85 : 225
      });
    }
    let wlan = null;
    for (let c = 0; c < net_columns.length; ++c)
      if (net_columns[c].role === "wlan") wlan = net_columns[c];

    // header and one row per net variable, one cell per available interface
    const net_header = [ { kind: "color", color: cyan },
      { kind: "font", font: 1 }, { kind: "text", text: "E" } ];
    for (let c = 0; c < net_columns.length; ++c) {
      net_header.push({ kind: "goto", x: net_columns[c].x },
        { kind: "font", font: 0 }, { kind: "text", text: net_columns[c].label });
    }
    net_header.push({ kind: "color", color: back });

    const net_row = function(icon, value) {
      const row = [ { kind: "goto", x: 50 },
        { kind: "font", font: 1 }, { kind: "text", text: icon },
        { kind: "font", font: 0 } ];
      for (let c = 0; c < net_columns.length; ++c) {
        row.push({ kind: "goto", x: net_columns[c].x },
          { kind: "text", text: value(net_columns[c].dev) });
      }
      return row;
    };

    const net_lines = [];
    if (net_columns.length > 0) {
      net_lines.push(net_header);
      net_lines.push(net_row("Ɓ ", function(dev) {
        return d.out_speed[dev] || d.human_readable(0);
      }));
      net_lines.push(net_row("Ƃ ", function(dev) {
        return d.up_speed[dev] || d.human_readable(0);
      }));
      net_lines.push(net_row("h ", function(dev) {
        return d.address[dev] || "0.0.0.0";
      }));
      if (wlan) {
        net_lines.push([ { kind: "goto", x: 50 },
          { kind: "font", font: 1 }, { kind: "text", text: "Ǘ " },
          { kind: "font", font: 0 },
          { kind: "goto", x: 85 },
          { kind: "text", text: d.essid + " : " + d.link_qual + "%" } ]);
      }
    }

    // one temperature per drive, separated by two spaces ("sda: 34 ºC")
    const temp_lines = [];
    const temps = d.hddtemps || [];
    if (temps.length > 0) {
      const cells = [];
      for (let i = 0; i < temps.length; ++i)
        cells.push(temps[i].dev + ": " + temps[i].temp + " ºC");
      temp_lines.push([ { kind: "goto", x: 50 },
        { kind: "font", font: 1 }, { kind: "text", text: "ǘ " },
        { kind: "font", font: 0 },
        { kind: "goto", x: 85 },
        { kind: "text", text: cells.join("  ") } ]);
    }

    return [
      // 1
      [ { kind: "color", color: "#000000" },
        { kind: "font", font: 2 }, { kind: "text", text: "ƃ " },
        { kind: "color", color: white },
        { kind: "font", font: 1 }, { kind: "text", text: "ǒ" },
        { kind: "font", font: 0 }, { kind: "text", text: d.uptime } ],
      // 2
      [ { kind: "hr", height: 2 } ],
      // 3
      [ { kind: "font", font: 0 },
        { kind: "text", text: d.distribution + " - " + d.kernel } ],
      // 4
      [],
      // 5-9: only the interfaces that are present and up
      ...net_lines,
      // 10
      [ { kind: "color", color: cyan },
        { kind: "font", font: 1 }, { kind: "text", text: "i " },
        { kind: "font", font: 0 }, { kind: "text", text: d.external_ip },
        { kind: "color", color: back } ],
      // 11
      [],
      // 12
      [ { kind: "color", color: cyan },
        { kind: "font", font: 1 }, { kind: "text", text: "ň " },
        { kind: "font", font: 0 }, { kind: "text", text: "HDD" },
        { kind: "color", color: back } ],
      // 13: one entry per drive, only for the drives that report a temperature
      ...temp_lines,
      // 14
      [ { kind: "goto", x: 50 },
        { kind: "font", font: 3 }, { kind: "text", text: "Ǒ " },
        { kind: "font", font: 0 },
        { kind: "goto", x: 85 }, { kind: "text", text: "Root:" },
        { kind: "goto", x: 140 },
        { kind: "bar", height: 7, width: 75, value: root_fs.frac, scale: 1 },
        { kind: "goto", x: 225 },
        { kind: "text", text: root_fs.perc + "% " + root_fs.free } ],
      // 15
      [ { kind: "goto", x: 50 },
        { kind: "font", font: 3 }, { kind: "text", text: "M " },
        { kind: "font", font: 0 },
        { kind: "goto", x: 70 }, { kind: "text", text: "alkeryn:" },
        { kind: "goto", x: 140 },
        { kind: "bar", height: 7, width: 75, value: home_fs.frac, scale: 1 },
        { kind: "goto", x: 225 },
        { kind: "text", text: home_fs.perc + "% " + home_fs.free } ],
      // 16
      [ { kind: "goto", x: 50 },
        { kind: "font", font: 3 }, { kind: "text", text: "M " },
        { kind: "font", font: 0 },
        { kind: "goto", x: 70 }, { kind: "text", text: "Stock:" },
        { kind: "goto", x: 140 },
        { kind: "bar", height: 7, width: 75, value: d.stock_frac, scale: 1 },
        { kind: "goto", x: 225 },
        { kind: "text", text: d.stock_perc + "% " + fs("/run/media/alkeryn/Stock").free } ],
      // 17: read/write rate of all physical drives together
      [ { kind: "goto", x: 50 },
        { kind: "text", text: "Read: " + all_disks().read },
        { kind: "goto", x: 225 },
        { kind: "text", text: " Write: " + all_disks().write } ],
      // 18
      [ { kind: "goto", x: 50 },
        { kind: "graph", height: 20, width: 80, color: theme.graph_read_color,
          data: all_disks().read_hist, scale: graph_scale(all_disks().read_hist) },
        { kind: "goto", x: 225 },
        { kind: "graph", height: 20, width: 80, color: theme.graph_write_color,
          data: all_disks().write_hist, scale: graph_scale(all_disks().write_hist) } ],
      // 19-20: dropped with the per-device read/write rows
      // 21
      [],
      // 22
      [ { kind: "color", color: cyan },
        { kind: "font", font: 1 }, { kind: "text", text: "Ŵ " },
        { kind: "font", font: 0 }, { kind: "text", text: "CPU" },
        { kind: "voffset", value: -5 },
        { kind: "goto", x: 225 },
        { kind: "font", font: 1 }, { kind: "text", text: "B " },
        { kind: "font", font: 0 }, { kind: "text", text: "RAM" },
        { kind: "color", color: back }, { kind: "font", font: 0 } ],
      // 23
      [ { kind: "goto", x: 50 },
        { kind: "text", text: d.cpu_percent[0] + "%" },
        { kind: "goto", x: 92 },
        { kind: "bar", height: 7, width: 80, value: d.cpu_percent[0] / 100, scale: 1 },
        { kind: "goto", x: 225 }, { kind: "text", text: "RAM:" },
        { kind: "goto", x: 268 }, { kind: "text", text: d.mem_perc + "%" },
        { kind: "goto", x: 302 },
        { kind: "bar", height: 7, width: 80, value: d.mem_frac, scale: 1 } ],
      // 24
      [ { kind: "goto", x: 50 },
        { kind: "text", text: d.cpu_percent[1] + "%" },
        { kind: "goto", x: 92 },
        { kind: "bar", height: 7, width: 80, value: d.cpu_percent[1] / 100, scale: 1 },
        { kind: "goto", x: 225 }, { kind: "text", text: "SWP:" },
        { kind: "goto", x: 268 }, { kind: "text", text: d.swap_perc + "%" },
        { kind: "goto", x: 302 },
        { kind: "bar", height: 7, width: 80, value: d.swap_frac, scale: 1 } ],
      // 25
      [ { kind: "goto", x: 50 },
        { kind: "text", text: d.cpu_percent[2] + "%" },
        { kind: "goto", x: 92 },
        { kind: "bar", height: 7, width: 80, value: d.cpu_percent[2] / 100, scale: 1 } ],
      // 26
      [ { kind: "goto", x: 50 },
        { kind: "text", text: d.cpu_percent[3] + "%" },
        { kind: "goto", x: 92 },
        { kind: "bar", height: 7, width: 80, value: d.cpu_percent[3] / 100, scale: 1 } ],
      // 27
      [],
      // 28
      [ { kind: "color", color: cyan },
        { kind: "font", font: 1 }, { kind: "text", text: "Ŷ " },
        { kind: "font", font: 0 }, { kind: "text", text: "Processus" } ],
      // 29
      [ { kind: "goto", x: 40 }, { kind: "text", text: "Name " },
        { kind: "goto", x: 170 }, { kind: "text", text: "PID" },
        { kind: "goto", x: 225 }, { kind: "text", text: "CPU" },
        { kind: "goto", x: 280 }, { kind: "text", text: "MEM" },
        { kind: "color", color: back } ],
      // 30-34
      [ { kind: "goto", x: 40 }, { kind: "text", text: top_name(0) },
        { kind: "goto", x: 170 }, { kind: "text", text: top_pid(0) },
        { kind: "goto", x: 225 }, { kind: "text", text: top_cpu(0) },
        { kind: "goto", x: 280 }, { kind: "text", text: top_mem(0) } ],
      [ { kind: "goto", x: 40 }, { kind: "text", text: top_name(1) },
        { kind: "goto", x: 170 }, { kind: "text", text: top_pid(1) },
        { kind: "goto", x: 225 }, { kind: "text", text: top_cpu(1) },
        { kind: "goto", x: 280 }, { kind: "text", text: top_mem(1) } ],
      [ { kind: "goto", x: 40 }, { kind: "text", text: top_name(2) },
        { kind: "goto", x: 170 }, { kind: "text", text: top_pid(2) },
        { kind: "goto", x: 225 }, { kind: "text", text: top_cpu(2) },
        { kind: "goto", x: 280 }, { kind: "text", text: top_mem(2) } ],
      [ { kind: "goto", x: 40 }, { kind: "text", text: top_name(3) },
        { kind: "goto", x: 170 }, { kind: "text", text: top_pid(3) },
        { kind: "goto", x: 225 }, { kind: "text", text: top_cpu(3) },
        { kind: "goto", x: 280 }, { kind: "text", text: top_mem(3) } ],
      [ { kind: "goto", x: 40 }, { kind: "text", text: top_name(4) },
        { kind: "goto", x: 170 }, { kind: "text", text: top_pid(4) },
        { kind: "goto", x: 225 }, { kind: "text", text: top_cpu(4) },
        { kind: "goto", x: 280 }, { kind: "text", text: top_mem(4) } ]
    ];
  }

  function compute_frame() {
    const empty = { width: 0, height: 0, texts: [], hrs: [], bars: [], graphs: [], end_x: 0, end_font: 0 };
    if (!theme || !fonts || !source || !fonts.ready) return empty;
    const rev = fonts.revision + source.revision; // binding dependencies
    const lines = win.build_lines();

    const border = win.border;
    const scale = win.theme.dpi_scale;

    // ---------------- sizing pass (text_size_updater) ----------------
    let text_w = scale(win.theme.minimum_width);
    let text_h = 0;
    let last_font_height = fonts.font_height(win.prev_end_font);
    let selected = win.prev_end_font;
    const stale = win.stale_cur_x;

    for (let i = 0; i < lines.length; ++i) {
      const line = lines[i];
      let w = 0;
      let cur_y_add = 0;
      for (let t = 0; t < line.length; ++t) {
        const tok = line[t];
        if (tok.kind === "text") {
          w += fonts.advance(selected, tok.text);
        } else if (tok.kind === "font") {
          selected = tok.font;
          if (fonts.font_height(selected) > last_font_height)
            last_font_height = fonts.font_height(selected);
        } else if (tok.kind === "goto") {
          const value = scale(tok.x);
          if (value > stale) w = value;
        } else if (tok.kind === "voffset") {
          last_font_height += scale(tok.value);
        } else if (tok.kind === "bar" || tok.kind === "graph") {
          w += scale(tok.width);
          const h = scale(tok.height);
          if (h > cur_y_add && h > fonts.font_height(selected))
            cur_y_add = h;
        }
      }
      if (w > text_w) text_w = w;
      text_h += last_font_height + cur_y_add;
      last_font_height = fonts.font_height(selected);
    }

    // the height is not clamped to conky's minimum_height: the rows are
    // dynamic (interfaces, drives), so the window follows the content
    text_w = text_w + 1;

    // ---------------- draw pass (draw_each_line_inner) ----------------
    const texts = [];
    const hrs = [];
    const bars = [];
    const graphs = [];
    let cur_y = border;
    let cur_x = border;
    let color = win.theme.default_color;
    selected = 0;
    let end_font = 0;

    for (let i = 0; i < lines.length; ++i) {
      const line = lines[i];
      let font_h = fonts.font_height(selected);
      cur_y += fonts.ascent(selected);
      cur_x = border;
      let cur_y_add = 0;
      let last_text = null;
      let last_kind = "";

      for (let t = 0; t < line.length; ++t) {
        const tok = line[t];
        last_kind = tok.kind;
        if (tok.kind === "text") {
          texts.push({
            x: cur_x,
            baseline: cur_y,
            font: selected,
            color: color,
            text: tok.text
          });
          last_text = texts[texts.length - 1];
          cur_x += fonts.advance(selected, tok.text);
        } else if (tok.kind === "font") {
          const old = fonts.ascent(selected);
          const next = fonts.ascent(tok.font);
          cur_y -= old;
          if (next < old) cur_y += old;
          else cur_y += next;
          selected = tok.font;
          font_h = fonts.font_height(selected);
          last_text = null;
        } else if (tok.kind === "goto") {
          cur_x = scale(tok.x);
          last_text = null;
        } else if (tok.kind === "color") {
          color = tok.color;
        } else if (tok.kind === "voffset") {
          cur_y += scale(tok.value);
        } else if (tok.kind === "hr") {
          const h = scale(tok.height);
          const mid = Math.floor(fonts.ascent(selected) / 2);
          const center = cur_y - Math.floor(mid / 2);
          const maxw = border + text_w - cur_x;
          let w = tok.width ? scale(tok.width) : 0;
          if (w <= 0 || w > maxw) w = maxw;
          hrs.push({ x: cur_x, center_y: center, width: w, height: h, color: color });
        } else if (tok.kind === "bar") {
          const h = scale(tok.height);
          let by = cur_y - Math.floor(fonts.ascent(selected) / 2) - 1;
          if (h < font_h) by -= Math.floor(h / 2) - 1;
          const w = scale(tok.width);
          bars.push({
            x: cur_x, y: by, width: w, height: h,
            fill: Math.trunc(w * tok.value / tok.scale),
            color: color
          });
          cur_x += w;
          if (h > cur_y_add && h > font_h) cur_y_add = h;
        } else if (tok.kind === "graph") {
          const h = scale(tok.height);
          let by = cur_y - Math.floor(fonts.ascent(selected) / 2) - 1;
          if (h < font_h) by -= Math.floor(h / 2) - 1;
          const w = scale(tok.width);
          graphs.push({
            x: cur_x, y: by, width: w, height: h,
            data: tok.data, scale: tok.scale, color: tok.color
          });
          cur_x += w;
          if (h > cur_y_add && h > font_h) cur_y_add = h;
        }
      }

      // conky adds the tall-graphic offset before drawing the trailing text
      if (cur_y_add > 0 && last_kind === "text" && last_text)
        last_text.baseline += cur_y_add;

      cur_y += cur_y_add;
      cur_y += fonts.descent(selected);
      end_font = selected;
    }

    return {
      width: text_w,
      height: text_h,
      texts: texts,
      hrs: hrs,
      bars: bars,
      graphs: graphs,
      end_x: cur_x,
      end_font: end_font
    };
  }

  Item {
    anchors.fill: parent
    clip: true

    Repeater {
      model: win.frame.texts
      delegate: ConkyText {
        required property var modelData
        theme: win.theme
        fonts: win.fonts
        font_index: modelData.font
        x: modelData.x
        text_baseline: modelData.baseline
        value: modelData.text
        text_color: modelData.color
      }
    }

    Repeater {
      model: win.frame.hrs
      delegate: ConkyHr {
        required property var modelData
        line_x: modelData.x
        line_center_y: modelData.center_y
        line_width: modelData.width
        line_height: modelData.height
        hr_color: modelData.color
      }
    }

    Repeater {
      model: win.frame.bars
      delegate: ConkyBar {
        required property var modelData
        bar_x: modelData.x
        bar_y: modelData.y
        bar_width: modelData.width
        bar_height: modelData.height
        fill_width: modelData.fill
        bar_color: modelData.color
      }
    }

    Repeater {
      model: win.frame.graphs
      delegate: ConkyGraph {
        required property var modelData
        graph_x: modelData.x
        graph_y: modelData.y
        graph_width: modelData.width
        graph_height: modelData.height
        graph_data: modelData.data
        graph_scale: modelData.scale
        graph_color: modelData.color
      }
    }
  }
}
