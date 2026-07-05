import QtQuick
import QtQuick.Layouts
import "../components"
import "../../Widgets/notifications"
import "../../core"

ColumnLayout {
  spacing: 12

  property string page: ""
  property var modeSvc: null
  property bool wifiEnabled: false
  property string wifiName: ""
  property var volumeIcon
  property real audioVolume: 0
  property bool audioMuted: false
  property var audioSink
  property var btAdapter
  property bool nlEnabled: false
  property bool doNotDisturb: false
  property var brightnessIcon
  property real brightness: 0
  property var activePlayer
  property string playerArt: ""
  property var storedNotifications: []
  onStoredNotificationsChanged: {
    var len = storedNotifications?.length ?? 0;
    if (notifHist) {
      notifHist.storedNotifications = storedNotifications;
      notifHist.Layout.preferredHeight = len > 0 ? 200 : 0;
    }
  }

  signal navigateTo(string page)
  signal toggleWifi()
  signal scanWifi()
  signal loadCurrentWifiPassword()
  signal toggleMute()
  signal toggleBluetooth()
  signal toggleNightLight()
  signal toggleDnd()
  signal setVolume(real val)
  signal setBrightness(real val)
  signal dismissNotif(var notifRef)
  signal clearNotifs()

  RowLayout {
    Layout.fillWidth: true
    spacing: 12

    ToggleTile {
      iconText: wifiEnabled ? "" : "󰖪"
      label: "Wi-Fi"
      sublabel: wifiEnabled ? wifiName : "Off"
      active: wifiEnabled
      expandable: true
      onTapped: toggleWifi()
      onExpandTapped: {
        navigateTo("wifi");
        scanWifi();
        loadCurrentWifiPassword();
      }
    }

    ToggleTile {
      iconText: "󰂯"
      label: "Bluetooth"
      sublabel: btAdapter?.enabled ? "On" : "Off"
      active: !!btAdapter?.enabled
      expandable: true
      onTapped: toggleBluetooth()
      onExpandTapped: navigateTo("bluetooth")
    }

    ToggleTile {
      iconText: volumeIcon(audioVolume, audioMuted)
      label: "Audio"
      sublabel: audioMuted ? "Muted" : (audioSink?.description || audioSink?.name || "Speaker")
      active: !audioMuted
      expandable: true
      onTapped: toggleMute()
      onExpandTapped: navigateTo("audio")
    }
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: 12

    ToggleTile {
      iconText: "󰂚"
      label: "Night Light"
      sublabel: nlEnabled ? "On" : "Off"
      active: nlEnabled
      expandable: true
      onTapped: toggleNightLight()
      onExpandTapped: navigateTo("nightlight")
    }

    ToggleTile {
      iconText: "󱐋"
      label: "Performance"
      sublabel: modeSvc ? modeSvc.currentMode.charAt(0).toUpperCase() + modeSvc.currentMode.slice(1) : "Balanced"
      active: true
      expandable: true
      onExpandTapped: navigateTo("mode")
    }

    ToggleTile {
      iconText: ""
      label: "Peace"
      sublabel: doNotDisturb ? "On" : "Off"
      active: doNotDisturb
      onTapped: toggleDnd()
    }
  }

  IconSlider {
    iconText: volumeIcon(audioVolume, audioMuted)
    value: audioMuted ? 0 : audioVolume
    onMoved: val => setVolume(val)
  }

  IconSlider {
    iconText: brightnessIcon(brightness)
    value: brightness
    onMoved: val => setBrightness(val)
  }

  // ---- Media Player Card ----
  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: 160
    radius: 18
    clip: true
    visible: activePlayer !== null
    color: Theme.surface

    Image {
      anchors.fill: parent
      source: playerArt || ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      sourceSize.width: 960
      sourceSize.height: 320
      visible: playerArt.length > 0 && status === Image.Ready
      opacity: 0.35
    }
    Rectangle {
      anchors.fill: parent
      color: Theme.overlay
      opacity: 0.8
    }

    RowLayout {
      anchors.fill: parent
      anchors.margins: 14
      spacing: 14

      Rectangle {
        width: 64
        height: 64
        radius: 14
        color: Theme.surfaceLight
        clip: true

        Image {
          id: artThumb
          anchors.fill: parent
          source: playerArt || ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          sourceSize.width: 128
          sourceSize.height: 128

          Rectangle {
            anchors.fill: parent
            color: Theme.surfaceLight
            visible: parent.status !== Image.Ready

            Text {
              anchors.centerIn: parent
              text: "󰎆"
              color: Theme.primary
              font { family: "JetBrainsMono Nerd Font"; pixelSize: 24 }
            }
          }
        }


      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 6

        Text {
          text: activePlayer?.identity || "Media Player"
          color: Theme.text
          opacity: 0.6
          elide: Text.ElideRight
          Layout.fillWidth: true
          font { family: "Inter"; pixelSize: 10 }
        }

        Text {
          text: activePlayer?.trackTitle || "Nothing playing"
          color: Theme.text
          font { family: "Inter"; pixelSize: 15; weight: 700 }
          elide: Text.ElideRight
          Layout.fillWidth: true
        }

        Text {
          text: activePlayer?.trackArtist || ""
          color: Theme.text
          opacity: 0.7
          elide: Text.ElideRight
          Layout.fillWidth: true
          font { family: "Inter"; pixelSize: 12 }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: 8
          Layout.topMargin: 2

          Text {
            text: "󰒮"
            color: Theme.subtext
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }
            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: activePlayer?.previous()
            }
          }

          Rectangle {
            id: playBtn
            width: 30
            height: 30
            radius: 15
            color: Theme.text

            Text {
              anchors.centerIn: parent
              text: activePlayer?.isPlaying ? "" : ""
              color: Theme.surface
              font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              hoverEnabled: true
              onEntered: playBtn.color = Theme.text
              onExited: playBtn.color = Theme.text
              onClicked: activePlayer?.togglePlaying()
            }
          }

          Text {
            text: "󰒭"
            color: Theme.subtext
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }
            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: activePlayer?.next()
            }
          }

          Rectangle {
            Layout.fillWidth: true
            height: 3
            radius: 1.5
            color: Theme.text
            opacity: 0.15
            Layout.alignment: Qt.AlignVCenter

            Rectangle {
              height: parent.height
              radius: 1.5
              color: Theme.text
              width: parent.width * (activePlayer && activePlayer.length > 0
                ? activePlayer.position / activePlayer.length
                : 0)
            }
          }
        }
      }
    }
  }

  NotificationHistory {
    id: notifHist
    Layout.fillWidth: true
    visible: true
    onDismissNotif: (notifRef) => dismissNotif(notifRef)
    onClearAll: clearNotifs()
  }

  Text {
    Layout.fillWidth: true
    Layout.topMargin: 8
    visible: storedNotifications.length === 0
    text: "No notifications"
    color: Theme.text
    opacity: 0.3
    horizontalAlignment: Text.AlignHCenter
    font { family: "Inter"; pixelSize: 12 }
  }

  Item { Layout.fillHeight: true }
}
