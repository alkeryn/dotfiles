#!/usr/bin/env bash
# Terminate already running bar instances
killall -q polybar &

export cpuid

for i in /sys/class/thermal/thermal_zone*/temp
do
    cat $i &>/dev/null && { cpuid="$i"; break; }
done
cpuid="$(echo $cpuid | cut -d"/" -f5 | sed 's/thermal_zone//g')"

# Wait until the processes have been shut down
while pgrep -x polybar >/dev/null; do sleep 1; done
while pgrep -x stalonetray >/dev/null; do sleep 1; done


# Launch bar1 and bar2
$mainpc && polybar mainpc -q &
$laptop && polybar laptop -q &
echo "Bars launched..."
