import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"

Item {
  id: root

  property string pendingSsid: ""
  property string connectError: ""
  property bool connecting: false

  signal dismiss()
  signal connectRequested(string ssid, string password)

  Rectangle {
    anchors.fill: parent
    visible: root.visible
    color: Theme.overlay

    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
  }

  Rectangle {
    visible: root.visible
    anchors.centerIn: parent
    width: 320
    height: pwCol.implicitHeight + 32
    radius: 18
    color: Theme.surfaceDim
    border.color: Theme.surface
    border.width: 1

    ColumnLayout {
      id: pwCol
      anchors.fill: parent
      anchors.margins: 16
      spacing: 10

      Text {
        text: "Connect to " + root.pendingSsid
        color: Theme.text
        font { family: "Inter"; pixelSize: 14; weight: 700 }
        Layout.fillWidth: true
        elide: Text.ElideRight
      }

      Rectangle {
        Layout.fillWidth: true
        height: 40
        radius: 10
        color: Theme.surface

        TextField {
          id: pwField
          anchors.fill: parent
          anchors.margins: 4
          color: Theme.text
          echoMode: revealBtn.checked ? TextInput.Normal : TextInput.Password
          placeholderText: "Password"
          placeholderTextColor: Theme.subtext
          background: null
          font { family: "Inter"; pixelSize: 13 }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        CheckBox {
          id: revealBtn
          text: "Show password"
          contentItem: Text { text: revealBtn.text; color: Theme.text; opacity: 0.7; leftPadding: revealBtn.indicator.width + 6; font { family: "Inter"; pixelSize: 11 } }
        }
      }

      Text {
        visible: root.connectError.length > 0
        text: root.connectError
        color: Theme.error
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        font { family: "Inter"; pixelSize: 11 }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 10
        Layout.topMargin: 4

        Rectangle {
          Layout.fillWidth: true
          height: 36
          radius: 10
          color: Theme.surface
          Text { anchors.centerIn: parent; text: "Cancel"; color: Theme.text; font { family: "Inter"; pixelSize: 12; weight: 600 } }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.dismiss(); pwField.text = ""; } }
        }
        Rectangle {
          Layout.fillWidth: true
          height: 36
          radius: 10
          color: Theme.primary
          Text { anchors.centerIn: parent; text: root.connecting ? "Connecting…" : "Connect"; color: Theme.primaryFg; font { family: "Inter"; pixelSize: 12; weight: 700 } }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            enabled: !root.connecting
            onClicked: {
              root.connectRequested(root.pendingSsid, pwField.text);
            }
          }
        }
      }
    }
  }
}
