#!/bin/sh
pkill compton;env WINEPREFIX=/home/alkeryn/App/wine/Osu wine /home/alkeryn/App/wine/Osu/drive_c/Osu/osu\!.exe;compton -b #--xrender-sync-fence
