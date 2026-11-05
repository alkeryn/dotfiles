import QtQuick

// [module/date]
// date = " %Y-%m-%d", time = %H:%M:%S
// format-prefix = <siji E016>, label = %date% %time%
Item {
  id: root

  required property var theme
  required property var fonts

  implicitHeight: theme.bar_height
  width: text.implicitWidth
  implicitWidth: width

  property string value: ""

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      const now = new Date();
      root.value = root.theme.date_string(now) + " " + root.theme.time_string(now);
    }
  }

  PolyText {
    id: text
    theme: root.theme
    fonts: root.fonts
    segments: [
      { text: "\ue016", color: root.theme.foreground_alt },
      { text: root.value, color: root.theme.foreground }
    ]
  }
}
