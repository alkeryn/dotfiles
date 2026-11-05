import QtQuick

// Bar metrics and colors, mirroring [bar/mainpc] and [bar/laptop] in the
// original polybar config.  Pixel values are physical pixels; launch.sh forces
// Qt's device pixel ratio to 1 so they map 1:1 on screen.
QtObject {
  id: theme

  property bool laptop: false

  readonly property int bar_height: laptop ? 35 : 27

  readonly property color background: "#70100000"
  readonly property color foreground: "#dfdfdf"
  readonly property color foreground_alt: "#f55"
  readonly property color background_alt: "#444"
  readonly property color secondary: "#e60053"
  readonly property color alert: "#bd2c40"

  readonly property color fs_mount: "#0a81f5"

  // Longest label kept before ellipsizing.  The window title and the mpd label
  // share the bar with every other module, so both stay bounded.
  readonly property int window_title_max: 60
  readonly property int music_label_max: 90

  // Wayland output names: mainpc uses HDMI-A-1, the laptop eDP-1.
  // Override with the MONITOR environment variable.
  readonly property string default_monitor: laptop ? "eDP-1" : "HDMI-A-1"

  function pad2(n) {
    return n < 10 ? "0" + n : "" + n;
  }

  function date_string(d) {
    return " " + d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
  }

  function time_string(d) {
    return pad2(d.getHours()) + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds());
  }

  // polybar label maxlen + ellipsis (label::get): truncate to maxlen-3 and
  // append "..." so the result is at most maxlen characters.
  function truncate(s, maxlen) {
    const chars = Array.from(s);
    if (maxlen <= 0 || chars.length <= maxlen) return s;
    return chars.slice(0, maxlen - 3).join("") + "...";
  }

  // polybar inline token spec `%title:min:max:suffix%` (label::replace_token):
  // truncate to max characters, then append the suffix.
  function truncate_token(s, maxlen, suffix) {
    const chars = Array.from(s);
    if (maxlen <= 0 || chars.length <= maxlen) return s;
    return chars.slice(0, maxlen).join("") + suffix;
  }
}
