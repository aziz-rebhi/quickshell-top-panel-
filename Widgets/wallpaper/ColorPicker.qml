import QtQuick
import QtQuick.Layouts
import "../../core"

Rectangle {
  id: root

  property var colors: []
  property var wallService: null
  property bool loading: false
  readonly property bool active: !loading && colors.length > 0
  signal dismissed()

  readonly property real bannerWidth: 480
  readonly property real bannerRadius: 28
  readonly property real bannerHeight: 144

  color: Theme.background
  clip: true

  layer.enabled: true
  layer.samples: 4

  RowLayout {
    id: content
    anchors.fill: parent
    anchors { leftMargin: 24; rightMargin: 20; topMargin: 18; bottomMargin: 16 }
    spacing: 14

    // Color preview stack (like notification app icon area)
    Rectangle {
      width: 42
      height: 42
      radius: 10
      color: loading ? Theme.surfaceVariant : (colors.length > 0 ? colors[0] : Theme.surfaceVariant)
      Layout.alignment: Qt.AlignTop

      Behavior on color { ColorAnimation { duration: 200 } }

      Text {
        anchors.centerIn: parent
        text: "󰈙"
        color: Theme.subtext
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 20 }
        visible: root.loading
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      spacing: 1

      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
          text: root.loading ? "Extracting colors…" : "Pick a source color"
          color: root.loading ? Theme.muted : Theme.text
          font { family: "Inter"; pixelSize: 13; weight: 700 }
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }

      RowLayout {
        spacing: 10
        Layout.topMargin: 8

        Repeater {
          model: root.loading ? 1 : root.colors.length

          delegate: Item {
            readonly property string hexColor: root.loading ? "" : root.colors[index]

            width: 36
            height: 36

            Rectangle {
              anchors.fill: parent
              radius: 8
              color: root.loading ? Theme.surfaceVariant : hexColor
              border.width: 2
              border.color: Theme.border

              Behavior on color { ColorAnimation { duration: 200 } }

              Rectangle {
                anchors.fill: parent
                radius: 6
                color: "transparent"
                border.width: ma.containsMouse ? 2 : 0
                border.color: Theme.primary
                Behavior on border.width { NumberAnimation { duration: 100 } }
              }

              Text {
                anchors.centerIn: parent
                text: "󰀬"
                color: Theme.subtext
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 16 }
                visible: root.loading
              }
            }

            MouseArea {
              id: ma
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              enabled: !root.loading && root.wallService !== null
              onClicked: {
                if (root.wallService)
                  root.wallService.applySourceColor(hexColor)
              }
            }
          }
        }
      }

      // "Use default" button
      Rectangle {
        Layout.topMargin: 6
        implicitWidth: defaultText.implicitWidth + 14
        implicitHeight: 20
        radius: 10
        color: Theme.surfaceLight

        Text {
          id: defaultText
          anchors.centerIn: parent
          text: "Use default"
          color: Theme.primary
          font { family: "Inter"; pixelSize: 10; weight: 600 }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.wallService)
              root.wallService.applyDefaultColor()
            else
              root.dismissed()
          }
        }
      }
    }

    Text {
      text: "󰅂"
      color: Theme.subtext
      font { family: "JetBrainsMono Nerd Font"; pixelSize: 16 }
      Layout.alignment: Qt.AlignTop | Qt.AlignRight
      Layout.topMargin: 0

      MouseArea {
        anchors.fill: parent
        anchors.margins: -8
        cursorShape: Qt.PointingHandCursor
        onClicked: root.dismissed()
      }
    }
  }

  states: [
    State {
      name: "active"
      when: active
      PropertyChanges { target: root; width: bannerWidth }
      PropertyChanges { target: root; height: bannerHeight }
      PropertyChanges { target: root; radius: bannerRadius }
      PropertyChanges { target: content; opacity: 1.0 }
    },
    State {
      name: "inactive"
      when: !active
      PropertyChanges { target: root; width: 0 }
      PropertyChanges { target: root; height: 0 }
      PropertyChanges { target: root; radius: 18 }
      PropertyChanges { target: content; opacity: 0.0 }
    }
  ]

  transitions: [
    Transition {
      from: "inactive"; to: "active"
      ParallelAnimation {
        NumberAnimation {
          target: root
          properties: "width,height,radius"
          duration: 400
          easing.type: Easing.InOutQuint
        }
        SequentialAnimation {
          PauseAnimation { duration: 150 }
          NumberAnimation {
            target: content
            property: "opacity"
            duration: 200
            easing.type: Easing.InOutQuint
          }
        }
      }
    },
    Transition {
      from: "active"; to: "inactive"
      ParallelAnimation {
        SequentialAnimation {
          NumberAnimation {
            target: content
            property: "opacity"
            duration: 100
          }
        }
        NumberAnimation {
          target: root
          properties: "width,height,radius"
          duration: 300
          easing.type: Easing.InOutQuint
        }
      }
    }
  ]
}
