import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import "../../core"

ScrollView {
  id: sv
  padding: 0
  ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
  ScrollBar.vertical.policy: ScrollBar.AsNeeded
  contentWidth: width

  required property string currentMode
  required property real cpuTemp
  required property string errorText

  signal setMode(string mode)
  signal backRequested()

  property var labels: {
    "silent": "Power Saver",
    "balanced": "Balanced",
    "performance": "Performance",
    "gaming": "Gaming",
    "ai": "AI"
  }

  ColumnLayout {
    width: parent.width
    spacing: 10

    Text {
      text: "Performance Mode"
      color: Theme.muted
      font { family: "Inter"; pixelSize: 11; weight: 700 }
      Layout.leftMargin: 4
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 64
        radius: 12
        color: currentMode === "silent" ? Theme.surfaceHover : Theme.surfaceLight

        ColumnLayout {
          anchors.centerIn: parent
          spacing: 2

          Text {
            text: "󰤆"
            color: currentMode === "silent" ? Theme.primary : Theme.subtext
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 16 }
            Layout.alignment: Qt.AlignHCenter
          }

          Text {
            text: "Silent"
            color: currentMode === "silent" ? Theme.text : Theme.subtext
            font { family: "Inter"; pixelSize: 12; weight: currentMode === "silent" ? 600 : 400 }
            Layout.alignment: Qt.AlignHCenter
          }

          Text {
            text: "quiet fan · power-saver"
            color: Theme.text
            opacity: 0.4
            font { family: "Inter"; pixelSize: 8 }
            Layout.alignment: Qt.AlignHCenter
          }

          Text {
            text: "CPU boost off"
            color: Theme.text
            opacity: 0.4
            font { family: "Inter"; pixelSize: 8 }
            Layout.alignment: Qt.AlignHCenter
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: setMode("silent")
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 64
        radius: 12
        color: currentMode === "balanced" ? Theme.surfaceHover : Theme.surfaceLight

        ColumnLayout {
          anchors.centerIn: parent
          spacing: 2

          Text {
            text: "󰒓"
            color: currentMode === "balanced" ? Theme.primary : Theme.subtext
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 16 }
            Layout.alignment: Qt.AlignHCenter
          }

          Text {
            text: "Balanced"
            color: currentMode === "balanced" ? Theme.text : Theme.subtext
            font { family: "Inter"; pixelSize: 12; weight: currentMode === "balanced" ? 600 : 400 }
            Layout.alignment: Qt.AlignHCenter
          }

          Text {
            text: "auto fan · smart CPU"
            color: Theme.text
            opacity: 0.4
            font { family: "Inter"; pixelSize: 8 }
            Layout.alignment: Qt.AlignHCenter
          }

          Text {
            text: "hybrid GPU"
            color: Theme.text
            opacity: 0.4
            font { family: "Inter"; pixelSize: 8 }
            Layout.alignment: Qt.AlignHCenter
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: setMode("balanced")
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 64
        radius: 12
        color: currentMode === "performance" ? Theme.surfaceHover : Theme.surfaceLight

        ColumnLayout {
          anchors.centerIn: parent
          spacing: 2

          Text {
            text: "󰓅"
            color: currentMode === "performance" ? Theme.primary : Theme.subtext
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 16 }
            Layout.alignment: Qt.AlignHCenter
          }

          Text {
            text: "Performance"
            color: currentMode === "performance" ? Theme.text : Theme.subtext
            font { family: "Inter"; pixelSize: 12; weight: currentMode === "performance" ? 600 : 400 }
            Layout.alignment: Qt.AlignHCenter
          }

          Text {
            text: "high fan · max CPU"
            color: Theme.text
            opacity: 0.4
            font { family: "Inter"; pixelSize: 8 }
            Layout.alignment: Qt.AlignHCenter
          }

          Text {
            text: "GPU always on"
            color: Theme.text
            opacity: 0.4
            font { family: "Inter"; pixelSize: 8 }
            Layout.alignment: Qt.AlignHCenter
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: setMode("performance")
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 64
        radius: 12
        color: currentMode === "gaming" ? Theme.surfaceHover : Theme.surfaceLight

        ColumnLayout {
          anchors.centerIn: parent
          spacing: 2

          Text {
            text: ""
            color: currentMode === "gaming" ? Theme.primary : Theme.subtext
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 16 }
            Layout.alignment: Qt.AlignHCenter
          }

          Text {
            text: "Gaming"
            color: currentMode === "gaming" ? Theme.text : Theme.subtext
            font { family: "Inter"; pixelSize: 12; weight: currentMode === "gaming" ? 600 : 400 }
            Layout.alignment: Qt.AlignHCenter
          }

          Text {
            text: "max fan · GPU persistence"
            color: Theme.text
            opacity: 0.4
            font { family: "Inter"; pixelSize: 8 }
            Layout.alignment: Qt.AlignHCenter
          }

          Text {
            text: "GameMode honored"
            color: Theme.text
            opacity: 0.4
            font { family: "Inter"; pixelSize: 8 }
            Layout.alignment: Qt.AlignHCenter
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: setMode("gaming")
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 64
        radius: 12
        color: currentMode === "ai" ? Theme.surfaceHover : Theme.surfaceLight

        ColumnLayout {
          anchors.centerIn: parent
          spacing: 2

          Text {
            text: "󰋛"
            color: currentMode === "ai" ? Theme.primary : Theme.subtext
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 16 }
            Layout.alignment: Qt.AlignHCenter
          }

          Text {
            text: "AI"
            color: currentMode === "ai" ? Theme.text : Theme.subtext
            font { family: "Inter"; pixelSize: 12; weight: currentMode === "ai" ? 600 : 400 }
            Layout.alignment: Qt.AlignHCenter
          }

          Text {
            text: "sustained · RAM-friendly"
            color: Theme.text
            opacity: 0.4
            font { family: "Inter"; pixelSize: 8 }
            Layout.alignment: Qt.AlignHCenter
          }

          Text {
            text: "GPU persistence"
            color: Theme.text
            opacity: 0.4
            font { family: "Inter"; pixelSize: 8 }
            Layout.alignment: Qt.AlignHCenter
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: setMode("ai")
        }
      }
    }

    Item { Layout.preferredHeight: 4 }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 48
      radius: 12
      color: Theme.surface

      RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        Text {
          text: "󰔄"
          color: cpuTemp > 0 ? (cpuTemp >= 85 ? Theme.error : Theme.primary) : Theme.subtext
          font { family: "JetBrainsMono Nerd Font"; pixelSize: 16 }
        }

        ColumnLayout {
          spacing: 1
          Layout.fillWidth: true

          Text {
            text: "CPU Temperature"
            color: Theme.text
            opacity: 0.6
            font { family: "Inter"; pixelSize: 10 }
          }

          Text {
            text: cpuTemp > 0 ? cpuTemp + "°C" : "—°C"
            color: cpuTemp >= 85 ? Theme.error : Theme.text
            font { family: "Inter"; pixelSize: 14; weight: 700 }
          }
        }

        Text {
          text: labels[currentMode] || "Balanced"
          color: Theme.primary
          font { family: "Inter"; pixelSize: 11; weight: 600 }
        }
      }
    }

    Text {
      text: "⚠ Hard modes (Performance/Gaming/AI) bypass the automatic fan curve. If CPU exceeds 88°C, the controller force-reverts to Balanced."
      color: Theme.text
      opacity: 0.4
      wrapMode: Text.WordWrap
      font { family: "Inter"; pixelSize: 9 }
      Layout.fillWidth: true
      Layout.topMargin: 2
    }

    Text {
      visible: errorText !== ""
      text: errorText
      color: Theme.error
      wrapMode: Text.WordWrap
      font { family: "Inter"; pixelSize: 9; weight: 600 }
      Layout.fillWidth: true
      Layout.topMargin: 2
    }

    Item { Layout.preferredHeight: 4 }
  }
}