import QtQuick

// Layout of the bar: left block, fixed-center block (laptop battery),
// right block and the systray reserved on the right.
Item {
  id: root

  required property var theme
  required property var fonts

  readonly property real module_gap: fonts.ready ? fonts.advance(0, "   ") : 0

  Row {
    id: left_row
    anchors.left: parent.left
    anchors.top: parent.top
    height: parent.height
    spacing: root.module_gap

    HyprlandWorkspaceModule {
      theme: root.theme
      fonts: root.fonts
    }

    HyprlandWindowModule {
      theme: root.theme
      fonts: root.fonts
    }
  }

  Row {
    id: right_row
    anchors.right: tray.has_content ? tray.left : parent.right
    anchors.top: parent.top
    height: parent.height
    spacing: root.module_gap

    BacklightModule {
      theme: root.theme
      fonts: root.fonts
      visible: root.theme.laptop && available
    }

    FilesystemModule {
      theme: root.theme
      fonts: root.fonts
    }

    MpdModule {
      theme: root.theme
      fonts: root.fonts
      visible: connected
    }

    VolumeModule {
      theme: root.theme
      fonts: root.fonts
      visible: available
    }

    KeyboardModule {
      theme: root.theme
      fonts: root.fonts
    }

    MemoryModule {
      theme: root.theme
      fonts: root.fonts
    }

    TemperatureModule {
      theme: root.theme
      fonts: root.fonts
      visible: available
    }

    CpuModule {
      theme: root.theme
      fonts: root.fonts
    }

    DateModule {
      theme: root.theme
      fonts: root.fonts
    }
  }

  BatteryModule {
    id: battery
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    theme: root.theme
    fonts: root.fonts
    visible: root.theme.laptop && available
  }

  TrayModule {
    id: tray
    anchors.right: parent.right
    anchors.top: parent.top
    theme: root.theme
    fonts: root.fonts
    visible: has_content
  }
}
