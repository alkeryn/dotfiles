#!/bin/sh
# Drive temperatures used by the Quickshell conky port.  One line per drive:
#   temp=/dev/<name> <celsius>
#
# conky.conf hardcoded ${hddtemp /dev/sda} and ${hddtemp /dev/sdb}.  The
# drives are discovered instead, one entry per physical block device:
#
#   1. the hddtemp daemon on 127.0.0.1:7634 (what conky's ${hddtemp} reads),
#   2. the kernel hwmon sensor of the drive: the nvme driver exposes one for
#      every NVMe controller, drivetemp does it for ATA/SATA disks.
#
# A drive reported by both appears once (the daemon value wins).

{
  # hddtemp daemon, one record per drive: |dev|model|temp|unit
  timeout 1 bash -c 'exec 3<>/dev/tcp/127.0.0.1/7634 && head -c 4096 <&3' 2>/dev/null |
    awk -F'|' '{
      for (i = 2; i + 2 <= NF; i += 5)
        if ($(i + 2) ~ /^[0-9]+$/)
          printf "temp=%s %s\n", $(i), $(i + 2)
    }'

  # hwmon sensors of every physical disk (partitions and dm/md mappings are
  # skipped, like the disk counters in conky_data.sh)
  for dir in /sys/block/*; do
    dev=${dir##*/}
    [ -e "$dir/device" ] || continue
    [ -e "$dir/partition" ] && continue
    # drivetemp hangs the sensor off the disk device, the nvme driver off the
    # controller (the device link, or the namespace's parent); accept whichever
    # reports.  Both the <dev>/hwmon/hwmonN and <dev>/hwmonN layouts exist.
    temp=""
    for base in "$dir/device" "$dir/.."; do
      [ -z "$temp" ] || break
      for file in "$base"/hwmon*/temp1_input "$base"/hwmon/hwmon*/temp1_input; do
        probe=$(cat "$file" 2>/dev/null) || continue
        case $probe in
          ''|*[!0-9]*) continue ;;
        esac
        temp=$probe
        break
      done
    done
    [ -n "$temp" ] || continue
    printf 'temp=/dev/%s %s\n' "$dev" "$((temp / 1000))"
  done
} | awk '!seen[$1]++'
