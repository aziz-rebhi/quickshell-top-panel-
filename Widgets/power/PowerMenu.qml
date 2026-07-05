import QtQuick
import QtQuick.Layouts
import "../../core"

Rectangle {
  id: powerMenu
  radius: parent?.radius ?? 28
  color: Theme.background
  clip: true

  property var powerAction: null
  property bool hovered: false

  RowLayout {
    anchors.centerIn: parent
    spacing: 20

    ColumnLayout {
      spacing: 6
      Layout.alignment: Qt.AlignHCenter
      Rectangle {
        Layout.alignment: Qt.AlignHCenter
        width: 50; height: 50; radius: 14
        color: btnMouse.containsMouse ? Theme.surfaceHover : Theme.surfaceLight
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
          anchors.centerIn: parent
          text: ""
          color: btnMouse.containsMouse ? Theme.text : Theme.error
          font { family: "JetBrainsMono Nerd Font"; pixelSize: 22 }
          Behavior on color { ColorAnimation { duration: 120 } }
        }
        MouseArea {
          id: btnMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: powerMenu.hovered = true
          onExited: powerMenu.hovered = false
          onClicked: if (powerMenu.powerAction) powerMenu.powerAction(["sh", "-c", "loginctl terminate-user $USER"])
        }
      }
      Text { text: "Logout"; color: Theme.text; opacity: 0.6; font.family: "Inter"; font.pixelSize: 10; Layout.alignment: Qt.AlignHCenter }
    }

    ColumnLayout {
      spacing: 6
      Layout.alignment: Qt.AlignHCenter
      Rectangle {
        Layout.alignment: Qt.AlignHCenter
        width: 50; height: 50; radius: 14
        color: lockBtnMouse.containsMouse ? Theme.surfaceHover : Theme.surfaceLight
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
          anchors.centerIn: parent
          text: ""
          color: lockBtnMouse.containsMouse ? Theme.text : Theme.secondary
          font { family: "JetBrainsMono Nerd Font"; pixelSize: 22 }
          Behavior on color { ColorAnimation { duration: 120 } }
        }
        MouseArea {
          id: lockBtnMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: powerMenu.hovered = true
          onExited: powerMenu.hovered = false
          onClicked: if (powerMenu.powerAction) powerMenu.powerAction(["hyprlock"])
        }
      }
      Text { text: "Lock"; color: Theme.text; opacity: 0.6; font.family: "Inter"; font.pixelSize: 10; Layout.alignment: Qt.AlignHCenter }
    }

    ColumnLayout {
      spacing: 6
      Layout.alignment: Qt.AlignHCenter
      Rectangle {
        Layout.alignment: Qt.AlignHCenter
        width: 50; height: 50; radius: 14
        color: sleepBtnMouse.containsMouse ? Theme.surfaceHover : Theme.surfaceLight
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
          anchors.centerIn: parent
          text: ""
          color: sleepBtnMouse.containsMouse ? Theme.text : Theme.tertiary
          font { family: "JetBrainsMono Nerd Font"; pixelSize: 22 }
          Behavior on color { ColorAnimation { duration: 120 } }
        }
        MouseArea {
          id: sleepBtnMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: powerMenu.hovered = true
          onExited: powerMenu.hovered = false
          onClicked: if (powerMenu.powerAction) powerMenu.powerAction(["systemctl", "suspend"])
        }
      }
      Text { text: "Sleep"; color: Theme.text; opacity: 0.6; font.family: "Inter"; font.pixelSize: 10; Layout.alignment: Qt.AlignHCenter }
    }

    ColumnLayout {
      spacing: 6
      Layout.alignment: Qt.AlignHCenter
      Rectangle {
        Layout.alignment: Qt.AlignHCenter
        width: 50; height: 50; radius: 14
        color: btnMouse2.containsMouse ? Theme.surfaceHover : Theme.surfaceLight
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
          anchors.centerIn: parent
          text: ""
          color: btnMouse2.containsMouse ? Theme.text : Theme.warning
          font { family: "JetBrainsMono Nerd Font"; pixelSize: 22 }
          Behavior on color { ColorAnimation { duration: 120 } }
        }
        MouseArea {
          id: btnMouse2
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: powerMenu.hovered = true
          onExited: powerMenu.hovered = false
          onClicked: if (powerMenu.powerAction) powerMenu.powerAction(["systemctl", "reboot"])
        }
      }
      Text { text: "Reboot"; color: Theme.text; opacity: 0.6; font.family: "Inter"; font.pixelSize: 10; Layout.alignment: Qt.AlignHCenter }
    }

    ColumnLayout {
      spacing: 6
      Layout.alignment: Qt.AlignHCenter
      Rectangle {
        Layout.alignment: Qt.AlignHCenter
        width: 50; height: 50; radius: 14
        color: btnMouse3.containsMouse ? Theme.surfaceHover : Theme.surfaceLight
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
          anchors.centerIn: parent
          text: ""
          color: btnMouse3.containsMouse ? Theme.text : Theme.error
          font { family: "JetBrainsMono Nerd Font"; pixelSize: 22 }
          Behavior on color { ColorAnimation { duration: 120 } }
        }
        MouseArea {
          id: btnMouse3
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: powerMenu.hovered = true
          onExited: powerMenu.hovered = false
          onClicked: if (powerMenu.powerAction) powerMenu.powerAction(["systemctl", "poweroff"])
        }
      }
      Text { text: "Shutdown"; color: Theme.text; opacity: 0.6; font.family: "Inter"; font.pixelSize: 10; Layout.alignment: Qt.AlignHCenter }
    }
  }
}
