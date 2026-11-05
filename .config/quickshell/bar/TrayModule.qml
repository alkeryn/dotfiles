import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// [bar/*] tray-position = right, tray-padding = 5
// Polybar's legacy tray uses a 16px icon.  Its spacing is
// (even(bar_height) - 16) / 2 + tray-padding, with one spacing on each side
// of every icon.
Item {
  id: root

  required property var theme
  required property var fonts

  implicitHeight: theme.bar_height

  readonly property int tray_height: theme.bar_height % 2 === 0 ? theme.bar_height : theme.bar_height - 1
  readonly property int icon_size: 16
  readonly property int spacing: (tray_height - icon_size) / 2 + 5
  readonly property int icon_y: (tray_height - icon_size) / 2
  readonly property int count: SystemTray.items.values ? SystemTray.items.values.length : 0
  readonly property bool has_content: count > 0

  property int network_signal: -1
  readonly property string network_icon: {
    if (network_signal < 0) return "";
    // These thresholds are exactly the ones nm-applet uses in
    // mobile_helper_get_quality_icon_name().  Show the plain link icon
    // (nm-signal-XX); the -secure variants are a libappindicator/SNI
    // data-menu detail, not the tray icon.
    let name = "nm-signal-00";
    if (network_signal > 80) name = "nm-signal-100";
    else if (network_signal > 55) name = "nm-signal-75";
    else if (network_signal > 30) name = "nm-signal-50";
    else if (network_signal > 5) name = "nm-signal-25";
    return Quickshell.iconPath(name);
  }

  implicitWidth: has_content ? spacing + count * (spacing + icon_size) : 0
  width: implicitWidth
  height: implicitHeight

  function open_menu(item, anchor) {
    if (!item || !item.hasMenu) return;
    const win = anchor.QsWindow.window;
    if (!win) return;
    const pos = anchor.QsWindow.itemPosition(anchor);
    item.display(win, Math.round(pos.x), Math.round(pos.y + anchor.height));
  }

  // nm-applet's SNI IconName is often a static app icon rather than the
  // signal-strength pixmap used by its legacy XEmbed tray icon.  Query the
  // in-use Wi-Fi signal and render the matching nm-signal-* icon instead.
  Process {
    id: nmcli
    command: ["nmcli", "-t", "-f", "IN-USE,SIGNAL", "dev", "wifi"]
    stdout: StdioCollector {
      id: nmcli_out
      onStreamFinished: {
        let signal = -1;
        const lines = nmcli_out.text.split(/\r?\n/);
        for (let i = 0; i < lines.length; ++i) {
          const line = lines[i];
          if (line.length === 0 || line.charAt(0) !== "*") continue;
          const parts = line.split(":");
          const value = parseInt(parts.length > 1 ? parts[1] : "", 10);
          if (!isNaN(value)) signal = value;
        }
        root.network_signal = signal;
      }
    }
  }

  function refresh_network() {
    if (nmcli.running) return;
    nmcli.running = true;
  }

  Timer {
    interval: 5000
    running: root.has_content
    repeat: true
    onTriggered: root.refresh_network()
  }

  Component.onCompleted: refresh_network()

  Repeater {
    model: SystemTray.items

    delegate: IconImage {
      required property var modelData
      required property int index

      readonly property bool is_network: {
        const id = ("" + (modelData.id || "")).toLowerCase();
        const title = ("" + (modelData.title || "")).toLowerCase();
        return id.indexOf("nm-applet") >= 0 || id.indexOf("network") >= 0
          || title.indexOf("network") >= 0;
      }

      x: root.spacing + index * (root.spacing + root.icon_size)
      y: root.icon_y
      width: root.icon_size
      height: root.icon_size
      implicitSize: root.icon_size
      // Prefer the plain nm-signal-XX link icon.  The SNI item can expose a
      // static app icon or an appindicator-style -secure variant instead.
      source: is_network && root.network_icon !== ""
        ? root.network_icon : modelData.icon

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: function(mouse) {
          if (mouse.button === Qt.MiddleButton) {
            modelData.secondaryActivate();
          } else if (modelData.hasMenu && (mouse.button === Qt.RightButton
                     || is_network || modelData.onlyMenu)) {
            root.open_menu(modelData, this);
          } else if (mouse.button === Qt.LeftButton) {
            modelData.activate();
          }
        }
        onWheel: function(wheel) {
          modelData.scroll(wheel.angleDelta.y, wheel.angleDelta.x !== 0);
        }
      }
    }
  }
}
