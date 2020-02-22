#!/bin/sh
pkill picom;env WINEPREFIX=/home/alkeryn/App/wine/Osu wine /home/alkeryn/App/wine/Osu/drive_c/Osu/osu\!.exe;picom -b #--xrender-sync-fence
