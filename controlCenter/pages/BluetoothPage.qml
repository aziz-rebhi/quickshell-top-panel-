import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Bluetooth
import "../../core"

ScrollView {
  id: sv
  padding: 0
  ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
  ScrollBar.vertical.policy: ScrollBar.AsNeeded
  contentWidth: width

  property var btAdapter
  property var btDevices
  property bool btScanning
  property var btDeviceSubtitle

  signal toggleBluetooth()
  signal toggleBtScan()
  signal forgetDevice(var device)
  signal pairDevice(var device)
  signal toggleBtConnection(var device)
  signal backRequested()

  ColumnLayout {
    width: parent.width
    spacing: 10

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 52
      radius: 14
      color: Theme.surface

      RowLayout {
        anchors.fill: parent
        anchors.margins: 14
        Text { text: "Bluetooth"; color: Theme.text; font { family: "Inter"; pixelSize: 14; weight: 700 } }
        Item { Layout.fillWidth: true }
        Rectangle {
          width: 46; height: 26; radius: 13
          color: btAdapter?.enabled ? Theme.primary : Theme.border
          Rectangle {
            width: 20; height: 20; radius: 10; color: Theme.backgroundFg
            anchors.verticalCenter: parent.verticalCenter
            x: btAdapter?.enabled ? parent.width - width - 3 : 3
            Behavior on x { NumberAnimation { duration: 120 } }
          }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: toggleBluetooth() }
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: 4
      spacing: 8

      Text {
        text: "Devices"
        color: Theme.text; opacity: 0.7
        font { family: "Inter"; pixelSize: 12; weight: 700 }
        Layout.fillWidth: true
      }

      Text {
        text: btScanning ? "Scanning…" : "Scan"
        color: Theme.primary
        font { family: "Inter"; pixelSize: 11; weight: 600 }
        MouseArea {
          anchors.fill: parent; anchors.margins: -6
          cursorShape: Qt.PointingHandCursor
          onClicked: toggleBtScan()
        }
      }
    }

    Repeater {
      model: btDevices

      delegate: Rectangle {
        id: btCard
        required property var modelData
        Layout.fillWidth: true
        Layout.preferredHeight: 56
        radius: 14
        color: modelData.state === BluetoothDeviceState.Connected ? Theme.surfaceLight : (modelData.pairing ? Theme.surfaceHover : Theme.surface)

        RowLayout {
          anchors.fill: parent
          anchors.margins: 14
          spacing: 10

          Text {
            text: modelData.pairing ? "󰄉" : (modelData.state === BluetoothDeviceState.Connected ? "󰂱" : "󰂯")
            color: modelData.state === BluetoothDeviceState.Connected ? Theme.primary : Theme.text
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 16 }
          }

          ColumnLayout {
            spacing: 0
            Layout.fillWidth: true
            Text { text: btCard.modelData.name || btCard.modelData.deviceName || "Unknown device"; color: Theme.text; elide: Text.ElideRight; Layout.fillWidth: true; font { family: "Inter"; pixelSize: 13; weight: 600 } }
            Text {
              text: btDeviceSubtitle(btCard.modelData)
              color: modelData.state === BluetoothDeviceState.Connected ? Theme.primary : Theme.text
              opacity: modelData.state === BluetoothDeviceState.Connected ? 1 : 0.6
              font { family: "Inter"; pixelSize: 10 }
            }
          }

          Text {
            text: modelData.pairing ? "" : (modelData.paired ? "Forget" : "Pair")
            visible: !modelData.pairing
            color: Theme.error
            font { family: "Inter"; pixelSize: 11; weight: 600 }
            MouseArea {
              anchors.fill: parent; anchors.margins: -8
              cursorShape: Qt.PointingHandCursor
              onClicked: modelData.paired ? forgetDevice(modelData) : pairDevice(modelData)
            }
          }

          Text {
            text: modelData.state === BluetoothDeviceState.Connected ? "Disconnect" : "Connect"
            visible: modelData.paired && !modelData.pairing
            color: Theme.primary
            font { family: "Inter"; pixelSize: 11; weight: 600 }
            MouseArea {
              anchors.fill: parent; anchors.margins: -8
              cursorShape: Qt.PointingHandCursor
              onClicked: toggleBtConnection(modelData)
            }
          }
        }
      }
    }

    Text {
      visible: btDevices.length === 0 && !btScanning
      text: btAdapter?.enabled ? "No devices found" : "Turn on Bluetooth to see devices"
      color: Theme.text; opacity: 0.4
      Layout.alignment: Qt.AlignHCenter
      Layout.topMargin: 12
      font { family: "Inter"; pixelSize: 12 }
    }

    Text {
      visible: btScanning && btDevices.length === 0
      text: "Scanning for devices…"
      color: Theme.primary; opacity: 0.6
      Layout.alignment: Qt.AlignHCenter
      Layout.topMargin: 12
      font { family: "Inter"; pixelSize: 12 }
    }

    Item { Layout.preferredHeight: 4 }
  }
}
