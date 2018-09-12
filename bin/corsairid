#!/bin/bash
#find the eventid of corsair keyboard and make a symlink in /dev/input for evdev passthrough
echo "Corsairid Launched"
until paths=`ls -d /sys/devices/virtual/input/input* 2>/dev/null`;do sleep 1; done
for x in $paths
do
        [ ! -d $x/mouse* ] && path=$x
done
event=$(ls -d $path/event*)
event=$(basename $event)
rm -f /dev/input/kbd
ln -s -f /dev/input/$event /dev/input/kbd
echo "Created /dev/input/kbd"
exit 0
