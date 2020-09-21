#!/usr/bin/env bash
# Terminate already running bar instances
killall -q polybar &

export hwmon

exp=(/sys/devices/platform/coretemp*/hwmon/hwmon*/temp1_input)
hwmon=$exp

# Wait until the processes have been shut down
while pgrep -x polybar >/dev/null; do sleep 1; done
while pgrep -x stalonetray >/dev/null; do sleep 1; done


# Launch bar1 and bar2
$mainpc && polybar mainpc -q &
$laptop && polybar laptop -q &
echo "Bars launched..."
