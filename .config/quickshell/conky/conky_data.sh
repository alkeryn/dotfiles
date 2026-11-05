#!/bin/sh
# Raw data used by the Quickshell conky port.  One line per sample:
#   key value...
# The deltas/formatting are computed in ConkyData.qml, mirroring conky.

# uptime in seconds
awk '{ printf "uptime=%d\n", $1 }' /proc/uptime 2>/dev/null

# distribution (conky reads NAME from os-release)
if [ -r /etc/os-release ]; then
  . /etc/os-release 2>/dev/null
  [ -n "$NAME" ] && printf 'dist=%s\n' "$NAME"
fi
printf 'kernel=%s\n' "$(uname -r)"

# ---- network -------------------------------------------------------------
# conky.conf hardcoded wlp6s0 and enp7s0.  Detect them instead: the first
# physical wireless and the first physical wired interface that is actually
# up (carrier/operstate, or holding an IPv4 address).  The layout only draws
# the interfaces reported here.
iface_up() {
  [ "$(cat "/sys/class/net/$1/operstate" 2>/dev/null)" = up ] && return 0
  [ "$(cat "/sys/class/net/$1/carrier" 2>/dev/null)" = 1 ] && return 0
  ip -4 -o addr show dev "$1" 2>/dev/null | grep -q ' inet ' && return 0
  return 1
}

wlan=""
wired=""
for dir in /sys/class/net/*; do
  dev=${dir##*/}
  [ "$dev" = lo ] && continue
  [ -e "$dir/device" ] || continue    # skip virtual interfaces (bridges, veth, ...)
  if [ -e "$dir/wireless" ] || [ -e "$dir/phy80211" ]; then
    [ -z "$wlan" ] || continue
    iface_up "$dev" && wlan=$dev
  else
    [ -z "$wired" ] || continue
    iface_up "$dev" && wired=$dev
  fi
done

[ -n "$wlan" ] && printf 'netif=wlan %s\n' "$wlan"
[ -n "$wired" ] && printf 'netif=eth %s\n' "$wired"

# network byte counters: iface rx tx.  /proc/net/dev pads the name with %6s,
# so a short name ("    lo:") gets a column that a 6+ character name
# ("wlp6s0:") does not have: neither the padding nor the field numbers are
# fixed.  Strip the padding, cut at the colon, then split the counters.
net_counters() {
  awk -v dev="$1" '
    {
      line = $0
      sub(/^[ \t]+/, "", line)
      colon = index(line, ":")
      if (colon == 0 || substr(line, 1, colon - 1) != dev) next
      rest = substr(line, colon + 1)
      sub(/^[ \t]+/, "", rest)
      n = split(rest, f, /[ \t]+/)
      if (n < 9) next          # rx bytes .. multicast, then tx bytes
      printf "net=%s %s %s\n", dev, f[1], f[9]
    }' /proc/net/dev 2>/dev/null
}

for dev in "$wlan" "$wired"; do
  [ -n "$dev" ] || continue
  net_counters "$dev"
done

# interface addresses (conky's $addrs shows 0.0.0.0 when there is none)
for dev in "$wlan" "$wired"; do
  [ -n "$dev" ] || continue
  addr=$(ip -4 -o addr show dev "$dev" 2>/dev/null | awk '{ print $4 }' | cut -d/ -f1 | head -n 1)
  printf 'addr=%s %s\n' "$dev" "${addr:-0.0.0.0}"
done

# default route and link state (used to detect network changes for $exec)
printf 'route=%s\n' "$(ip route show default 2>/dev/null | head -n 1)"
for dev in "$wlan" "$wired"; do
  [ -n "$dev" ] || continue
  printf 'link=%s %s\n' "$dev" "$(cat "/sys/class/net/$dev/operstate" 2>/dev/null)"
done

# wireless essid + link quality (percent of 100)
essid=""
if [ -n "$wlan" ]; then
  if command -v iwgetid >/dev/null 2>&1; then
    essid=$(iwgetid -r "$wlan" 2>/dev/null)
  elif command -v iw >/dev/null 2>&1; then
    essid=$(iw dev "$wlan" info 2>/dev/null | awk '/^[[:space:]]*ssid /{ print $2; exit }')
  fi
fi
printf 'essid=%s\n' "$essid"
# wireless link quality and signal level, same %6s padding as /proc/net/dev:
#   wlp6s0: 0000   57.  -53.  -256  ...
# status, quality (of 70 on mac80211), level in dBm, noise in dBm.
qual=0
level=0
if [ -n "$wlan" ] && [ -r /proc/net/wireless ]; then
  set -- $(awk -v dev="$wlan" '
    {
      line = $0
      sub(/^[ \t]+/, "", line)
      colon = index(line, ":")
      if (colon == 0 || substr(line, 1, colon - 1) != dev) next
      rest = substr(line, colon + 1)
      sub(/^[ \t]+/, "", rest)
      n = split(rest, f, /[ \t]+/)
      if (n < 3) next          # status, quality, level
      printf "%d %d\n", f[2] + 0, f[3] + 0
    }' /proc/net/wireless 2>/dev/null)
  qual=${1:-0}
  level=${2:-0}
fi
# mac80211 only fills /proc/net/wireless when wext is available; ask nl80211
# (iw) for the signal level when neither value came through (a level of 0 or
# below -110 dBm is the driver's "unknown" marker, e.g. -256)
if [ "$qual" -le 0 ] && { [ "$level" -eq 0 ] || [ "$level" -lt -110 ]; } &&
   command -v iw >/dev/null 2>&1; then
  level=$(iw dev "$wlan" link 2>/dev/null |
    awk '/^[[:space:]]*signal:/ { printf "%.0f", $2; exit }')
  [ -n "$level" ] || level=0
fi
printf 'linkqual=%s\n' "$qual"
printf 'linklevel=%s\n' "$level"

# filesystem: path frsize blocks bfree bavail
for path in / /home/alkeryn /run/media/alkeryn/Stock; do
  set -- $(stat -f -c '%S %b %f %a' "$path" 2>/dev/null)
  printf 'fs=%s %s %s %s %s\n' "$path" "${1:-0}" "${2:-0}" "${3:-0}" "${4:-0}"
done

# disk sector counters for every physical block device: device read write.
# Partitions, loop/ram/zram devices and dm/md mappings are skipped so the
# "all drives" total in ConkyData.qml counts each I/O once, at the real disk.
for dir in /sys/block/*; do
  dev=${dir##*/}
  [ -e "$dir/device" ] || continue
  [ -e "$dir/partition" ] && continue
  set -- $(awk -v dev="$dev" '$3 == dev { print $6, $10 }' /proc/diskstats 2>/dev/null)
  printf 'disk=%s %s %s\n' "$dev" "${1:-0}" "${2:-0}"
done

# per-core jiffies: index user nice system idle iowait irq softirq steal
awk '/^cpu[0-9]/ { printf "cpu=%s %s %s %s %s %s %s %s %s\n", substr($1, 4), $2, $3, $4, $5, $6, $7, $8, $9 }' /proc/stat 2>/dev/null

# memory in kB (conky uses MemAvailable with no_buffers = true)
awk '
  /^MemTotal:/     { t = $2 }
  /^MemAvailable:/ { a = $2 }
  /^SwapTotal:/    { st = $2 }
  /^SwapFree:/     { sf = $2 }
  END { printf "mem=%d %d\nswap=%d %d\n", t, a, st, sf }
' /proc/meminfo 2>/dev/null

# processes: pid utime stime rss_pages name (name last: it may contain spaces)
awk '
  {
    line = $0
    sub(/^[0-9]+ \(.*\) /, "", line)
    n = split(line, a, " ")
    if (n < 22) next
    name = $0
    sub(/^[0-9]+ \(/, "", name)
    sub(/\) .*$/, "", name)
    printf "proc=%d %s %s %s %s\n", $1, a[12], a[13], a[22], name
  }
' /proc/[0-9]*/stat 2>/dev/null

# aggregate cpu jiffies (all fields of the "cpu " line)
ncpu=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
awk -v ncpu="$ncpu" '/^cpu / { t = 0; for (i = 2; i <= 9; i++) t += $i; printf "cpucount=%d\ntotaltick=%d\n", ncpu, t }' /proc/stat 2>/dev/null
