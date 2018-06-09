# Terminate already running bar instances
killall -q polybar &
# Wait until the processes have been shut down
while pgrep -x polybar >/dev/null; do sleep 1; done
while pgrep -x stalonetray >/dev/null; do sleep 1; done
# Launch bar1 and bar2
$mainpc && polybar mainpc -q &
echo "Bars launched..."
