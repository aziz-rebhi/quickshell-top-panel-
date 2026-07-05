import QtQuick
import QtQuick.Layouts
import "../../core"

Item {
  id: root

  property bool isOpen: false
  property var wallpaperModel: []
  property var wallService: null

  signal closed()

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape) {
      close()
      event.accepted = true
    }
  }

  opacity: root.isOpen ? 1 : 0
  visible: root.isOpen || opacity > 0
  Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuart } }

  // Dim backdrop
  Rectangle {
    anchors.fill: parent
    color: Theme.background
    opacity: root.isOpen ? 0.55 : 0
    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuart } }
  }

  // Click-outside catcher
  MouseArea {
    anchors.fill: parent
    enabled: root.isOpen
    onClicked: {
      var p = mapToItem(panel, mouse.x, mouse.y)
      if (!(p.x >= 0 && p.x <= panel.width && p.y >= 0 && p.y <= panel.height))
        close()
    }
  }

  // Centered panel
  Rectangle {
    id: panel
    radius: 16

    readonly property real maxWidth: Math.min(parent.width * 0.85, 760)
    readonly property real maxHeight: Math.min(parent.height * 0.8, 540)
    width: maxWidth
    height: maxHeight

    color: Theme.surface
    border.width: 1
    border.color: Theme.border

    transform: [
      Translate {
        y: root.isOpen ? 0 : 30
        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutQuart } }
      },
      Scale {
        origin.x: panel.width / 2
        origin.y: panel.height / 2
        xScale: root.isOpen ? 1 : 0.95
        yScale: root.isOpen ? 1 : 0.95
        Behavior on xScale { NumberAnimation { duration: 200; easing.type: Easing.OutQuart } }
        Behavior on yScale { NumberAnimation { duration: 200; easing.type: Easing.OutQuart } }
      }
    ]

    anchors.centerIn: parent

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 16
      spacing: 12

      // Header
      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
          text: "󰸉"
          color: Theme.accent
          font { family: "JetBrainsMono Nerd Font"; pixelSize: 16 }
        }

        Text {
          text: "Wallpapers"
          color: Theme.text
          font { family: "Inter"; pixelSize: 14; weight: Font.Bold }
          Layout.fillWidth: true
        }

        Text {
          text: "󰅖"
          color: Theme.subtext
          font { family: "JetBrainsMono Nerd Font"; pixelSize: 14 }
          MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            cursorShape: Qt.PointingHandCursor
            onClicked: close()
          }
        }
      }

      // Grid container
      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 12
        color: Theme.surfaceDim
        clip: true

        WallpaperGrid {
          id: wallpaperGrid
          anchors.fill: parent
          anchors.margins: 10
          wallpaperModel: root.wallpaperModel
          wallService: root.wallService
          onWallpaperChosen: function(path) {
            root.close()
          }
        }
      }
    }
  }

  Timer {
    id: closeTimer
    interval: 200
    onTriggered: root.closed()
  }

  function open() {
    closeTimer.stop()
    root.isOpen = true
    root.forceActiveFocus()
  }

  function close() {
    root.isOpen = false
    closeTimer.restart()
  }
}
