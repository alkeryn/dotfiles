import QtQuick
import Quickshell
import Quickshell.Io

// All conky variables used by conky.conf, with conky's own update logic and
// number formatting (human_readable(), round_to_positive_int(), the top
// process lists, ...).
Item {
  id: root

  required property var theme
  property bool active: true

  property bool ready: false
  property int revision: 0

  // ---- values exposed to the layout -------------------------------------
  property string uptime: ""
  property string distribution: ""
  property string kernel: ""
  property string external_ip: ""

  // drive temperatures: [{ dev: "sda", temp: "34" }, ...] in a stable order
  property var hddtemps: []

  // The public IP is looked up only when it is unknown, when the network
  // changed, or when the last successful lookup is older than
  // ip_refresh_interval.  CONKY_IP_INTERVAL overrides the interval (seconds).
  readonly property int ip_refresh_interval: {
    const value = parseInt(Quickshell.env("CONKY_IP_INTERVAL"));
    return isNaN(value) || value < 10 ? 300000 : value * 1000;
  }
  readonly property int ip_retry_interval: 30000
  property bool ip_dirty: true
  property double ip_last_attempt: 0
  property double ip_last_success: 0
  property string ip_fetch_signature: ""
  property string net_signature: ""

  // interfaces found by conky_data.sh: [{ role: "wlan"|"eth", dev: "..." }]
  property var net_interfaces: []
  property var out_speed: ({})
  property var up_speed: ({})
  property var address: ({})

  property string essid: ""
  // raw values from conky_data.sh: /proc/net/wireless quality (of 70 on
  // mac80211) and signal level in dBm
  property int link_quality: 0
  property int link_level: 0
  // ${wireless_link_qual_perc}: quality / max_quality * 100
  property int link_qual: 0
  readonly property int link_quality_max: 70

  // filesystems: path -> { perc, free, frac }
  property var filesystems: ({})
  property int stock_perc: 0
  property real stock_frac: 0

  // disk io: dev -> { read, write, read_hist, write_hist } plus the "total"
  // pseudo device aggregating every physical disk
  property var disks: ({})

  property var cpu_percent: [0, 0, 0, 0]
  property int mem_perc: 0
  property real mem_frac: 0
  property int swap_perc: 0
  property real swap_frac: 0

  // top processes: name/pid/cpu from the cpu-sorted list, mem from the
  // mem-sorted list (that is what ${top ...} does in conky)
  property var top_rows: []

  // ---- raw state --------------------------------------------------------
  property var prev: ({})
  property double prev_time: 0
  property var cpu_state: ({})
  property var proc_state: ({})

  readonly property int sample_count: 2

  function num(v) {
    const n = parseFloat(v);
    return isNaN(n) ? 0 : n;
  }

  // conky's human_readable()
  function human_readable(value) {
    const suffixes = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"];
    let n = num(value);
    if (Math.abs(n) < 1000)
      return fixed(n, 0) + suffixes[0];
    let idx = 0;
    while (Math.abs(Math.trunc(n / 1024)) >= 1000 && idx + 2 < suffixes.length) {
      n /= 1024;
      idx++;
    }
    idx++;
    const fnum = n / 1024;
    let precision = 0;
    if (fnum < 99.95) precision = 1;
    if (fnum < 9.995) precision = 2;
    return fixed(fnum, precision) + suffixes[idx];
  }

  // printf("%.*f") with the locale decimal separator, no grouping
  function fixed(value, precision) {
    const s = Number(value).toFixed(precision);
    const point = Qt.locale().decimalPoint;
    return point === "." ? s : s.replace(".", point);
  }

  // uptime formatting from conky's format_seconds()
  function uptime_string(seconds) {
    let s = Math.floor(seconds);
    const days = Math.floor(s / 86400);
    s %= 86400;
    const hours = Math.floor(s / 3600);
    s %= 3600;
    const minutes = Math.floor(s / 60);
    s %= 60;
    if (days > 0)
      return days + "d " + hours + "h " + minutes + "m";
    return hours + "h " + minutes + "m " + s + "s";
  }

  function fs_info(spec) {
    // spec: frsize blocks bfree bavail
    const frsize = num(spec[0]);
    const total = frsize * num(spec[1]);
    const free = frsize * num(spec[2]);
    const avail = frsize * num(spec[3]);
    if (total <= 0)
      return { perc: 0, free: human_readable(0), frac: 0 };
    const used = (total - free) / total;
    return {
      // conky truncates the uint8_t percentage
      perc: Math.floor(used * 100),
      free: human_readable(avail),
      frac: used
    };
  }

  // conky's diskio values: the sector delta since the previous sample,
  // averaged over diskio_avg_samples (2) samples, in bytes, with a 100 point
  // history for the graphs
  function disk_entry(previous, read_kb, write_kb) {
    const prev = previous || { read_bytes: 0, write_bytes: 0, read_hist: [], write_hist: [] };
    const read_bytes = (read_kb * 1024 + prev.read_bytes) / 2;
    const write_bytes = (write_kb * 1024 + prev.write_bytes) / 2;
    return {
      read: human_readable(read_bytes),
      write: human_readable(write_bytes),
      read_hist: push_history(prev.read_hist, read_bytes),
      write_hist: push_history(prev.write_hist, write_bytes),
      read_bytes: read_bytes,
      write_bytes: write_bytes
    };
  }

  // a device that disappeared has no I/O left; keep its history at zero
  function empty_disk_entry(previous) {
    const prev = previous || {};
    return {
      read: human_readable(0),
      write: human_readable(0),
      read_hist: push_history(prev.read_hist, 0),
      write_hist: push_history(prev.write_hist, 0),
      read_bytes: 0,
      write_bytes: 0
    };
  }

  // conky divides the quality by the driver's max_qual, which iwlib reports
  // as 70 for mac80211; drivers that only report a level get the usual dBm
  // mapping (0..100% for -100..-50 dBm) instead.  A level outside -110..-1 dBm
  // is the driver's "unknown" marker (-256 on mac80211), so it is ignored.
  function link_qual_percent(quality, level) {
    let perc = 0;
    if (quality > 0)
      perc = quality * 100 / root.link_quality_max;
    else if (level < 0 && level >= -110)
      perc = 2 * (level + 100);
    else if (level > 0)
      perc = level;
    return Math.max(0, Math.min(100, Math.round(perc)));
  }

  function push_history(history, value) {
    const next = (history || []).slice();
    next.unshift(value);
    if (next.length > 100) next.length = 100;
    return next;
  }

  // "temp=/dev/sda 34" lines produced by conky_temps.sh
  function parse_temps(text) {
    const temps = [];
    const lines = (text || "").split("\n");
    for (let i = 0; i < lines.length; ++i) {
      const line = lines[i];
      const eq = line.indexOf("=");
      if (eq < 0 || line.substring(0, eq) !== "temp") continue;
      const parts = line.substring(eq + 1).trim().split(" ");
      if (parts.length < 2) continue;
      temps.push({
        dev: parts[0].replace(/^\/dev\//, ""),
        temp: parts[1]
      });
    }
    return temps;
  }

  function script(name) {
    const path = Qt.resolvedUrl(name).toString().replace("file://", "");
    return ["sh", "-c", "sh '" + path.replace(/'/g, "'\\''") + "'"];
  }

  Process {
    id: sampler
    command: root.script("conky_data.sh")
    stdout: StdioCollector {
      onStreamFinished: root.apply(this.text)
    }
  }

  Timer {
    interval: 1000
    running: root.active
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!sampler.running) sampler.running = true
  }

  // ${exec curl -s -4 ifconfig.co | grep ...}
  Process {
    id: ip_fetch
    command: ["sh", "-c",
      "curl -s -4 --max-time 4 ifconfig.co 2>/dev/null | grep -E -o '([0-9]{1,3}[\\.]){3}[0-9]{1,3}'"]
    stdout: StdioCollector {
      onStreamFinished: {
        const value = this.text.trim();
        if (value === "") {
          // keep the last known address, retry after ip_retry_interval
          return;
        }
        root.external_ip = value;
        root.ip_last_success = Date.now();
        // do not clear the flag if the network changed during the lookup
        // (an empty stored signature means it was not known when we started)
        if (root.ip_fetch_signature === ""
            || root.ip_fetch_signature === root.net_signature)
          root.ip_dirty = false;
      }
    }
  }

  function maybe_fetch_ip() {
    if (!root.active || ip_fetch.running) return;
    const now = Date.now();
    const unknown = root.external_ip === "";
    const stale = now - root.ip_last_success >= root.ip_refresh_interval;
    // nothing to do: we know the address and it is still fresh
    if (!root.ip_dirty && !unknown && !stale) return;
    // a network change wins; otherwise space out attempts (failures included)
    const spacing = unknown
      ? root.ip_retry_interval
      : Math.min(root.ip_retry_interval, root.ip_refresh_interval);
    if (!root.ip_dirty && now - root.ip_last_attempt < spacing) return;
    root.ip_last_attempt = now;
    root.ip_fetch_signature = root.net_signature;
    ip_fetch.running = true;
  }

  Timer {
    interval: 1000
    running: root.active
    repeat: true
    triggeredOnStart: true
    onTriggered: root.maybe_fetch_ip()
  }

  // drive temperatures: hddtemp daemon + drivetemp hwmon, all drives found
  Process {
    id: hdd
    command: root.script("conky_temps.sh")
    stdout: StdioCollector {
      onStreamFinished: root.hddtemps = root.parse_temps(this.text)
    }
  }

  Timer {
    interval: 5000
    running: root.active
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!hdd.running) hdd.running = true
  }

  // the two ${execbar 7,75 df | awk /stock/...} style commands
  Process {
    id: stock
    command: ["sh", "-c",
      "df 2>/dev/null | awk /stock/'{x+=$3;y=x/(x+$4)*100} END {print int(y)}'"]
    stdout: StdioCollector {
      onStreamFinished: {
        const v = root.num(this.text.trim());
        root.stock_perc = v;
        root.stock_frac = v / 100;
      }
    }
  }

  Timer {
    interval: 1000
    running: root.active
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!stock.running) stock.running = true
  }

  function apply(text) {
    const now = Date.now();
    const raw = {};
    const lines = text.split("\n");
    for (let i = 0; i < lines.length; ++i) {
      const line = lines[i];
      if (!line) continue;
      const eq = line.indexOf("=");
      if (eq < 0) continue;
      const key = line.substring(0, eq);
      if (!raw[key]) raw[key] = [];
      raw[key].push(line.substring(eq + 1));
    }

    // ---- uptime / system -------------------------------------------------
    if (raw.uptime && raw.uptime[0] !== undefined)
      root.uptime = root.uptime_string(root.num(raw.uptime[0]));
    if (raw.dist && raw.dist[0] !== undefined)
      root.distribution = raw.dist[0];
    if (raw.kernel && raw.kernel[0] !== undefined)
      root.kernel = raw.kernel[0];

    // ---- network ---------------------------------------------------------
    const speeds_out = {};
    const speeds_up = {};
    const net_prev = root.prev.net || {};
    if (raw.net) {
      for (let i = 0; i < raw.net.length; ++i) {
        const parts = raw.net[i].split(" ");
        const dev = parts[0];
        const rx = root.num(parts[1]);
        const tx = root.num(parts[2]);
        let drx = 0;
        let dtx = 0;
        let last_rx = 0;
        let last_tx = 0;
        if (net_prev[dev]) {
          drx = Math.max(0, rx - net_prev[dev][0]);
          dtx = Math.max(0, tx - net_prev[dev][1]);
          last_rx = net_prev[dev][2] || 0;
          last_tx = net_prev[dev][3] || 0;
        }
        // conky averages the last net_avg_samples (2) instantaneous speeds
        const avg_rx = (drx + last_rx) / 2;
        const avg_tx = (dtx + last_tx) / 2;
        speeds_out[dev] = root.human_readable(avg_rx);
        speeds_up[dev] = root.human_readable(avg_tx);
        net_prev[dev] = [rx, tx, drx, dtx];
      }
    }
    const netifs = [];
    if (raw.netif) {
      for (let i = 0; i < raw.netif.length; ++i) {
        const parts = raw.netif[i].split(" ");
        if (parts.length > 1) netifs.push({ role: parts[0], dev: parts[1] });
      }
    }
    root.net_interfaces = netifs;

    // rebuilt every sample so a vanished interface does not leave an address
    const addresses = {};
    if (raw.addr) {
      for (let i = 0; i < raw.addr.length; ++i) {
        const parts = raw.addr[i].split(" ");
        addresses[parts[0]] = parts.slice(1).join(" ");
      }
    }
    root.address = addresses;
    if (raw.essid && raw.essid[0] !== undefined) root.essid = raw.essid[0];
    if (raw.linkqual && raw.linkqual[0] !== undefined)
      root.link_quality = root.num(raw.linkqual[0]);
    if (raw.linklevel && raw.linklevel[0] !== undefined)
      root.link_level = root.num(raw.linklevel[0]);
    root.link_qual = root.link_qual_percent(root.link_quality, root.link_level);

    // A change of addresses, default route or link state means the public IP
    // may have changed: trigger a lookup.
    const signature = JSON.stringify([
      raw.addr || [],
      raw.route || [],
      raw.link || []
    ]);
    if (root.net_signature !== "" && signature !== root.net_signature)
      root.ip_dirty = true;
    root.net_signature = signature;

    // ---- filesystems -----------------------------------------------------
    const fs = {};
    if (raw.fs) {
      for (let i = 0; i < raw.fs.length; ++i) {
        const parts = raw.fs[i].split(" ");
        fs[parts[0]] = root.fs_info(parts.slice(1));
      }
    }
    root.filesystems = fs;

    // ---- disk io ---------------------------------------------------------
    const disk_prev = root.prev.disk || {};
    const disks = {};
    const hist = root.disks;
    let total_read_kb = 0;
    let total_write_kb = 0;
    if (raw.disk) {
      for (let i = 0; i < raw.disk.length; ++i) {
        const parts = raw.disk[i].split(" ");
        const dev = parts[0];
        const reads = root.num(parts[1]);
        const writes = root.num(parts[2]);
        let read_kb = 0;
        let write_kb = 0;
        if (disk_prev[dev]) {
          read_kb = Math.max(0, reads - disk_prev[dev][0]) / 2;
          write_kb = Math.max(0, writes - disk_prev[dev][1]) / 2;
        }
        total_read_kb += read_kb;
        total_write_kb += write_kb;
        disks[dev] = root.disk_entry(hist[dev], read_kb, write_kb);
        disk_prev[dev] = [reads, writes];
      }
    }
    // every physical disk together, used by the "all drives" read/write lines
    disks.total = root.disk_entry(hist.total, total_read_kb, total_write_kb);
    // devices that disappeared keep their history at zero
    for (const dev in hist) {
      if (dev !== "total" && !disks[dev])
        disks[dev] = root.empty_disk_entry(hist[dev]);
    }
    root.disks = disks;

    // ---- cpu -------------------------------------------------------------
    const dt = root.prev_time > 0 ? (now - root.prev_time) / 1000 : 0;
    root.prev_time = now;
    if (raw.cpu && dt > 0.001) {
      const percents = [];
      for (let i = 0; i < raw.cpu.length; ++i) {
        const parts = raw.cpu[i].split(" ");
        const index = root.num(parts[0]);
        const user = root.num(parts[1]);
        const nice = root.num(parts[2]);
        const system = root.num(parts[3]);
        const idle = root.num(parts[4]);
        const iowait = root.num(parts[5]);
        const irq = root.num(parts[6]);
        const softirq = root.num(parts[7]);
        const steal = root.num(parts[8]);
        const total = user + nice + system + idle + iowait + irq + softirq + steal;
        const active = total - (idle + iowait);
        const state = root.cpu_state[index] || { total: total, active: active, prev: 0 };
        const delta = total - state.total;
        let usage = 0;
        if (delta === 0)
          usage = 1;
        else
          usage = (active - state.active) / delta;
        // conky averages the last two samples
        const avg = (usage + (state.prev || 0)) / root.sample_count;
        percents[index] = Math.round(avg * 100);
        root.cpu_state[index] = { total: total, active: active, prev: usage };
      }
      root.cpu_percent = percents;
    }

    // ---- memory ----------------------------------------------------------
    if (raw.mem && raw.mem[0]) {
      const parts = raw.mem[0].split(" ");
      const total = root.num(parts[0]);
      const avail = root.num(parts[1]);
      if (total > 0) {
        const used = total - avail;
        root.mem_perc = Math.round(used * 100 / total);
        root.mem_frac = used / total;
      }
    }
    if (raw.swap && raw.swap[0]) {
      const parts = raw.swap[0].split(" ");
      const total = root.num(parts[0]);
      const free = root.num(parts[1]);
      if (total > 0) {
        const used = total - free;
        root.swap_perc = Math.round(used * 100 / total);
        root.swap_frac = used / total;
      }
    }

    // ---- processes -------------------------------------------------------
    const memmax = (raw.mem && raw.mem[0])
      ? root.num(raw.mem[0].split(" ")[0]) : 0;
    let total_delta = 0;
    if (raw.totaltick && raw.totaltick[0] !== undefined) {
      const total_ticks = root.num(raw.totaltick[0]);
      if (root.prev.total_ticks !== undefined)
        total_delta = Math.max(0, total_ticks - root.prev.total_ticks);
      root.prev.total_ticks = total_ticks;
    }
    if (raw.cpucount && raw.cpucount[0] !== undefined)
      root.prev.cpu_count = root.num(raw.cpucount[0]);

    if (raw.proc && total_delta > 0) {
      const list = [];
      for (let i = 0; i < raw.proc.length; ++i) {
        const parts = raw.proc[i].split(" ");
        const pid = root.num(parts[0]);
        const ticks = root.num(parts[1]) + root.num(parts[2]);
        const rss = root.num(parts[3]) * 4096;
        // the process name is last and may contain spaces
        const name = parts.slice(4).join(" ");
        const old = root.proc_state[pid];
        const delta_ticks = old !== undefined ? Math.max(0, ticks - old) : 0;
        list.push({
          pid: pid,
          name: name,
          amount: total_delta > 0 ? 100 * delta_ticks / total_delta : 0,
          rss: rss
        });
        root.proc_state[pid] = ticks;
      }
      // drop dead pids
      const alive = {};
      for (let i = 0; i < list.length; ++i) alive[list[i].pid] = true;
      for (const pid in root.proc_state)
        if (!alive[pid]) delete root.proc_state[pid];

      const by_cpu = list.slice().sort(function(a, b) { return b.amount - a.amount; });
      const by_mem = list.slice().sort(function(a, b) { return b.rss - a.rss; });
      const rows = [];
      for (let i = 0; i < 5; ++i) {
        const c = by_cpu[i];
        const m = by_mem[i];
        rows.push({
          name: c ? c.name : "",
          pid: c ? c.pid : 0,
          cpu: c ? c.amount : 0,
          mem: m && memmax > 0 ? (m.rss / memmax) / 10 : 0
        });
      }
      root.top_rows = rows;
    }

    root.out_speed = speeds_out;
    root.up_speed = speeds_up;
    root.prev.net = net_prev;
    root.prev.disk = disk_prev;
    root.ready = true;
    root.revision += 1;
  }
}
