import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"

ScrollView {
  id: sv
  padding: 0
  ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
  ScrollBar.vertical.policy: ScrollBar.AsNeeded
  contentWidth: width

  property bool wifiEnabled: false
  property string wifiName: ""
  property string wifiSecurity: ""
  property var wifiNetworks: []
  property bool wifiScanning: false
  property bool wifiConnecting: false
  property string wifiQrPath: ""
  property string wifiCurrentPassword: ""
  property bool wifiPasswordRevealed: false

  signal toggleWifi()
  signal scanWifi()
  signal connectToWifi(string ssid, string security, string password)
  signal loadCurrentWifiPassword()
  signal backRequested()
  signal disconnectWifi()
  signal generateWifiQr()
  signal showQrCode(string path)
  signal requestPassword(string ssid)

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
        Text { text: "Wi-Fi"; color: Theme.text; font { family: "Inter"; pixelSize: Fonts.title; weight: 700 } }
        Item { Layout.fillWidth: true }
        Rectangle {
          width: 46; height: 26; radius: 13
          color: wifiEnabled ? Theme.primary : Theme.border
          Rectangle {
            width: 20; height: 20; radius: 10; color: Theme.backgroundFg
            anchors.verticalCenter: parent.verticalCenter
            x: wifiEnabled ? parent.width - width - 3 : 3
            Behavior on x { NumberAnimation { duration: 120 } }
          }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: toggleWifi() }
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      visible: wifiEnabled && wifiName !== "No network" && wifiName !== "Off"
      Layout.preferredHeight: connectedCol.implicitHeight + 28
      radius: 16
      color: Theme.container
      border.color: Theme.primary
      border.width: 1

      ColumnLayout {
        id: connectedCol
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        RowLayout {
          Layout.fillWidth: true
          Text { text: ""; color: Theme.primary; font { family: "JetBrainsMono Nerd Font"; pixelSize: Fonts.heading } }
          ColumnLayout {
            spacing: 0
            Layout.fillWidth: true
            Text { text: wifiName; color: Theme.text; font { family: "Inter"; pixelSize: Fonts.title; weight: 700 } }
            Text { text: "Connected"; color: Theme.primary; font { family: "Inter"; pixelSize: Fonts.small } }
          }
          Item { Layout.fillWidth: true }
          Text {
            text: "Disconnect"
            color: Theme.text; opacity: 0.7
            font { family: "Inter"; pixelSize: Fonts.small; weight: 600 }
            MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: disconnectWifi() }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          visible: wifiCurrentPassword.length > 0
          spacing: 8

          Text { text: "Password:"; color: Theme.text; opacity: 0.7; font { family: "Inter"; pixelSize: Fonts.body } }
          Text {
            text: wifiPasswordRevealed ? wifiCurrentPassword : Array(Math.max(6, wifiCurrentPassword.length) + 1).join("•")
            color: Theme.text
            font { family: "JetBrainsMono Nerd Font"; pixelSize: Fonts.body }
            Layout.fillWidth: true
          }
          Text {
            text: wifiPasswordRevealed ? "󰋭" : "󰋬"
            color: Theme.text
            font { family: "JetBrainsMono Nerd Font"; pixelSize: Fonts.icon }
            MouseArea {
              anchors.fill: parent; anchors.margins: -8
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                wifiPasswordRevealed = !wifiPasswordRevealed;
                if (wifiPasswordRevealed && !wifiQrPath) generateWifiQr();
              }
            }
          }
        }

        Image {
          visible: wifiPasswordRevealed && wifiQrPath.length > 0
          source: wifiQrPath
          Layout.preferredWidth: 140
          Layout.preferredHeight: 140
          Layout.alignment: Qt.AlignHCenter
          fillMode: Image.PreserveAspectFit
          smooth: false
        }

        Text {
          visible: wifiPasswordRevealed && wifiCurrentPassword.length === 0
          text: "No saved password found for this network."
          color: Theme.text; opacity: 0.5
          font { family: "Inter"; pixelSize: Fonts.small }
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: 4
      Text { text: "Networks"; color: Theme.text; opacity: 0.7; font { family: "Inter"; pixelSize: Fonts.body; weight: 700 } }
      Item { Layout.fillWidth: true }
      Text {
        visible: wifiScanning
        text: "󰑓"
        color: Theme.primary
        font { family: "JetBrainsMono Nerd Font"; pixelSize: Fonts.title }
        RotationAnimation on rotation {
          from: 0; to: 360; duration: 1000; loops: Animation.Infinite; running: wifiScanning
        }
      }
      Text {
        text: wifiScanning ? "Scanning…" : "Refresh"
        color: Theme.primary
        font { family: "Inter"; pixelSize: Fonts.small; weight: 600 }
        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: scanWifi() }
      }
    }

    Repeater {
      model: wifiNetworks

      delegate: Rectangle {
        required property var modelData
        Layout.fillWidth: true
        Layout.preferredHeight: 52
        radius: 14
        color: modelData.active ? Theme.surfaceLight : Theme.surface

        RowLayout {
          anchors.fill: parent
          anchors.margins: 14
          spacing: 10

          Text {
            text: modelData.signal > 75 ? "󰤨" : modelData.signal > 50 ? "󰤥" : modelData.signal > 25 ? "󰤢" : "󰤟"
            color: Theme.text
            font { family: "JetBrainsMono Nerd Font"; pixelSize: Fonts.title }
          }

          ColumnLayout {
            spacing: 0
            Layout.fillWidth: true
            Text { text: modelData.ssid; color: Theme.text; elide: Text.ElideRight; Layout.fillWidth: true; font { family: "Inter"; pixelSize: Fonts.subtitle; weight: 600 } }
            Text {
              text: modelData.active ? "Connected" : (modelData.security && modelData.security !== "--" ? "Secured" : "Open")
              color: modelData.active ? Theme.primary : Theme.text
              opacity: modelData.active ? 1 : 0.6
              font { family: "Inter"; pixelSize: Fonts.caption }
            }
          }

          Text {
            visible: modelData.security && modelData.security !== "--"
            text: "󰲛"
            color: Theme.text; opacity: 0.5
            font { family: "JetBrainsMono Nerd Font"; pixelSize: Fonts.iconSmall }
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (modelData.active) return;
            if (modelData.security && modelData.security !== "--") {
              requestPassword(modelData.ssid);
            } else {
              connectToWifi(modelData.ssid, modelData.security || "", "");
            }
          }
        }
      }
    }

    Text {
      visible: wifiNetworks.length === 0 && !wifiScanning
      text: "No networks found"
      color: Theme.text; opacity: 0.4
      Layout.alignment: Qt.AlignHCenter
      Layout.topMargin: 12
      font { family: "Inter"; pixelSize: Fonts.body }
    }

    Item { Layout.preferredHeight: 4 }
  }
}
