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
  property var wifiSaved: []
  property bool wifiScanning: false
  property bool wifiConnecting: false
  property string wifiQrPath: ""
  property string wifiCurrentPassword: ""
  property bool wifiPasswordRevealed: false
  property string wifiPendingSsid: ""
  property string wifiConnectError: ""
  property string wifiForgetError: ""

  signal toggleWifi()
  signal scanWifi()
  signal connectToWifi(string ssid, string security, string password)
  signal loadCurrentWifiPassword()
  signal backRequested()
  signal disconnectWifi()
  signal forgetWifi(string ssid, string uuid)
  signal generateWifiQr()
  signal showQrCode(string path)
  signal requestPassword(string ssid)
  signal cancelPassword()

  // Page-local UI state only. None of this needs ControlCenter to know about it.
  property bool showQr: false
  // One armed delete at a time, so two confirm strips can never be open at once.
  property string forgetArmed: ""

  readonly property bool isConnected: wifiEnabled
    && wifiName.length > 0
    && wifiName !== "No network"
    && wifiName !== "Off"

  // The connected network's saved profile, if there is one. Drives the hero's
  // signal reading and its Forget action.
  readonly property var currentEntry: {
    if (!isConnected) return null
    for (var i = 0; i < wifiSaved.length; i++)
      if (wifiSaved[i].ssid === wifiName) return wifiSaved[i]
    return null
  }

  // The hero already shows the connected network, so both lists drop it. The
  // active flags can lag a poll behind, so the SSID is compared as well.
  readonly property var visibleNetworks: {
    var out = []
    for (var i = 0; i < wifiNetworks.length; i++)
      if (wifiNetworks[i].ssid !== wifiName) out.push(wifiNetworks[i])
    return out
  }
  readonly property var savedList: {
    var out = []
    for (var i = 0; i < wifiSaved.length; i++)
      if (wifiSaved[i].ssid !== wifiName) out.push(wifiSaved[i])
    return out
  }

  // Deliberately not the SSID: the hero card right below already names it, and
  // the header is for state, not identity.
  readonly property string headerStatus: !wifiEnabled ? "Off"
    : (wifiScanning ? "Scanning…" : (isConnected ? "Connected" : "Not connected"))
  readonly property string headerStatusColor: isConnected ? Theme.primary : Theme.muted

  // Four bars instead of a glyph: strength is readable at a glance, and the
  // weakest bar is still a bar rather than a different character.
  component SignalBars: Item {
    id: bars
    // Named strength, not signal: `signal` is a QML keyword, and leaning on the
    // engine tolerating it as a property name is not a risk worth carrying.
    property int strength: 0
    property bool dimmed: false
    readonly property int level: strength > 75 ? 4 : strength > 50 ? 3 : strength > 25 ? 2 : strength > 0 ? 1 : 0
    implicitWidth: 17
    implicitHeight: 14
    Row {
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      spacing: 1.5
      Repeater {
        model: 4
        delegate: Rectangle {
          required property int index
          width: 3
          height: 4 + index * 3
          radius: 1.5
          color: index < bars.level ? (bars.level >= 3 ? Theme.primary : Theme.text) : Theme.border
          opacity: bars.dimmed ? 0.35 : 1
        }
      }
    }
  }

  // Small text-button idiom shared by Disconnect / Forget / Refresh. The
  // negative margins are the hit area, so the label can sit tight to the edge.
  component GhostButton: Text {
    id: ghost
    signal tapped()
    property bool subdued: false
    property bool armed: false
    color: armed ? Theme.danger : (subdued ? Theme.text : Theme.primary)
    opacity: armed ? 0.9 : (subdued ? 0.7 : 1)
    font { family: "Inter"; pixelSize: Fonts.small; weight: 600 }
    MouseArea {
      anchors.fill: parent; anchors.margins: -6
      cursorShape: Qt.PointingHandCursor
      onClicked: ghost.tapped()
    }
  }

  ColumnLayout {
    width: parent.width
    spacing: 8

    // ---- 1. MASTER TOGGLE ----
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 48
      radius: 14
      color: Theme.surface

      RowLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        ColumnLayout {
          spacing: 1
          Layout.fillWidth: true
          Text {
            text: "Wi-Fi"
            color: Theme.text
            font { family: "Inter"; pixelSize: Fonts.subtitle; weight: 700 }
          }
          Text {
            text: sv.headerStatus
            color: sv.headerStatusColor
            elide: Text.ElideRight
            Layout.fillWidth: true
            font { family: "Inter"; pixelSize: Fonts.caption }
          }
        }

        Rectangle {
          width: 46; height: 26; radius: 13
          color: wifiEnabled ? Theme.primary : Theme.border
          Rectangle {
            width: 20; height: 20; radius: 10; color: Theme.backgroundFg
            anchors.verticalCenter: parent.verticalCenter
            x: wifiEnabled ? parent.width - width - 3 : 3
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
          }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: toggleWifi() }
        }
      }
    }

    // ---- 2. CONNECTED HERO ----
    Rectangle {
      Layout.fillWidth: true
      visible: sv.isConnected
      Layout.preferredHeight: heroCol.implicitHeight + 28
      radius: 16
      color: Theme.container
      border.color: Theme.primary
      border.width: 1

      ColumnLayout {
        id: heroCol
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        RowLayout {
          Layout.fillWidth: true
          spacing: 12

          SignalBars {
            strength: sv.currentEntry ? sv.currentEntry.signal : 0
            dimmed: !sv.currentEntry
            Layout.alignment: Qt.AlignVCenter
          }

          ColumnLayout {
            spacing: 1
            Layout.fillWidth: true
            Text {
              text: sv.wifiName
              color: Theme.text
              elide: Text.ElideRight
              Layout.fillWidth: true
              font { family: "Inter"; pixelSize: Fonts.title; weight: 700 }
            }
            Text {
              text: sv.wifiSecurity.length > 0 ? "Connected · " + sv.wifiSecurity : "Connected"
              color: Theme.primary
              elide: Text.ElideRight
              Layout.fillWidth: true
              font { family: "Inter"; pixelSize: Fonts.caption }
            }
          }

          RowLayout {
            spacing: 10
            Layout.alignment: Qt.AlignVCenter

            GhostButton {
              text: "Disconnect"
              subdued: true
              visible: sv.forgetArmed === ""
              onTapped: disconnectWifi()
            }
            GhostButton {
              text: "Cancel"
              visible: sv.forgetArmed !== "" && sv.forgetArmed === sv.wifiName
              onTapped: sv.forgetArmed = ""
            }
            GhostButton {
              text: "Forget"
              armed: true
              visible: sv.forgetArmed === sv.wifiName
              onTapped: {
                if (sv.currentEntry) forgetWifi(sv.currentEntry.ssid, sv.currentEntry.uuid)
                sv.forgetArmed = ""
              }
            }
            GhostButton {
              text: "Forget"
              armed: true
              visible: sv.forgetArmed === "" && sv.currentEntry !== null
              onTapped: sv.forgetArmed = sv.wifiName
            }
          }
        }

        // Armed on the connected network: deleting the profile you are on drops
        // the link, so say so before it happens.
        Text {
          Layout.fillWidth: true
          visible: sv.forgetArmed === sv.wifiName
          text: "The saved password is deleted and you will be disconnected. You will need it again to reconnect."
          color: Theme.danger
          wrapMode: Text.WordWrap
          font { family: "Inter"; pixelSize: Fonts.caption }
        }

        Rectangle {
          Layout.fillWidth: true
          visible: sv.wifiCurrentPassword.length > 0
          // 40, not 36: the Nerd Font eye and QR glyphs are Fonts.icon (14) but
          // their line box is 19px, so a 36px row squeezed them by 3px.
          Layout.preferredHeight: 40
          radius: 10
          color: Theme.surface

          RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            Text {
              text: "Password"
              color: Theme.muted
              font { family: "Inter"; pixelSize: Fonts.caption }
            }
            Text {
              text: sv.wifiPasswordRevealed
                ? sv.wifiCurrentPassword
                : Array(Math.max(8, sv.wifiCurrentPassword.length) + 1).join("•")
              color: Theme.text
              elide: Text.ElideRight
              Layout.fillWidth: true
              font { family: "JetBrainsMono Nerd Font"; pixelSize: Fonts.body }
            }
            Text {
              text: sv.wifiPasswordRevealed ? "󰋭" : "󰋬"
              color: Theme.text; opacity: 0.8
              font { family: "JetBrainsMono Nerd Font"; pixelSize: Fonts.icon }
              MouseArea {
                anchors.fill: parent; anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  sv.wifiPasswordRevealed = !sv.wifiPasswordRevealed
                  if (!sv.wifiPasswordRevealed) sv.showQr = false
                }
              }
            }
            Text {
              text: "󰇁"
              color: sv.showQr ? Theme.primary : Theme.text
              opacity: sv.showQr ? 1 : 0.55
              font { family: "JetBrainsMono Nerd Font"; pixelSize: Fonts.icon }
              MouseArea {
                anchors.fill: parent; anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  sv.showQr = !sv.showQr
                  // Reveal alongside it: the QR carries the password, so a
                  // masked password next to a visible code would be a lie.
                  if (sv.showQr) {
                    sv.wifiPasswordRevealed = true
                    if (!sv.wifiQrPath) generateWifiQr()
                  }
                }
              }
            }
          }
        }

        Text {
          Layout.fillWidth: true
          visible: sv.wifiPasswordRevealed && sv.wifiCurrentPassword.length === 0
          text: "No saved password for this network."
          color: Theme.muted
          font { family: "Inter"; pixelSize: Fonts.caption }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.topMargin: 2
          visible: sv.showQr && sv.wifiPasswordRevealed && sv.wifiQrPath.length > 0
          Layout.preferredHeight: 132
          radius: 12
          color: Theme.surfaceBright

          Image {
            anchors.centerIn: parent
            width: 120; height: 120
            source: sv.wifiQrPath
            fillMode: Image.PreserveAspectFit
            smooth: false
          }
        }
      }
    }

    // ---- OFF STATE ----
    Text {
      Layout.fillWidth: true
      visible: !wifiEnabled
      text: "Wi-Fi is turned off"
      color: Theme.text; opacity: 0.45
      horizontalAlignment: Text.AlignHCenter
      Layout.topMargin: 18
      Layout.bottomMargin: 18
      font { family: "Inter"; pixelSize: Fonts.body }
    }

    // ---- 3. AVAILABLE NETWORKS ----
    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: wifiEnabled ? 4 : 0
      visible: wifiEnabled
      spacing: 8

      Text {
        text: "Networks"
        color: Theme.text; opacity: 0.7
        font { family: "Inter"; pixelSize: Fonts.body; weight: 700 }
      }
      Item { Layout.fillWidth: true }
      Text {
        visible: wifiScanning
        text: "󰑓"
        color: Theme.primary
        font { family: "JetBrainsMono Nerd Font"; pixelSize: Fonts.body }
        RotationAnimation on rotation {
          from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: wifiScanning
        }
      }
      GhostButton {
        text: wifiScanning ? "Scanning…" : "Refresh"
        onTapped: scanWifi()
      }
    }

    Repeater {
      model: sv.visibleNetworks
      // Fades while a rescan is in flight so the list reads as refreshing
      // rather than as a hard swap of rows.
      opacity: wifiScanning ? 0.55 : 1
      Behavior on opacity { NumberAnimation { duration: 180 } }

      delegate: Rectangle {
        id: netCard
        required property var modelData
        // A Repeater parents its items to the Repeater's *parent*, so the
        // delegates are siblings of this object, not children. Hiding the
        // Repeater would leave every row on screen; the gate has to be here.
        visible: sv.wifiEnabled
        Layout.fillWidth: true
        Layout.preferredHeight: expanded ? entryCol.implicitHeight + 24 : 48
        radius: 14
        color: netHover.hovered ? Theme.surfaceBright : Theme.surface

        property bool expanded: wifiPendingSsid === modelData.ssid
        property bool connecting: wifiConnecting && wifiPendingSsid === modelData.ssid
        property bool pwReveal: false

        function startConnect() {
          if (!expanded || connecting) return;
          connectToWifi(modelData.ssid, modelData.security || "secured", pwField.text);
        }

        onExpandedChanged: {
          if (expanded) {
            pwField.forceActiveFocus();
            focusTimer.restart();
          }
        }

        Timer {
          id: focusTimer
          interval: 100
          repeat: false
          onTriggered: {
            if (expanded) pwField.forceActiveFocus();
          }
        }

        HoverHandler { id: netHover }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          // No double-taps while a connect is already in flight.
          enabled: !connecting
          onClicked: {
            if (modelData.saved || !modelData.security || modelData.security === "--") {
              connectToWifi(modelData.ssid, modelData.security || "", "");
            } else if (expanded) {
              cancelPassword();
            } else {
              requestPassword(modelData.ssid);
            }
          }
        }

        ColumnLayout {
          id: entryCol
          anchors.fill: parent
          anchors.margins: 12
          spacing: 8

          RowLayout {
            Layout.fillWidth: true
            spacing: 12

            SignalBars {
              strength: modelData.signal
              Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
              spacing: 1
              Layout.fillWidth: true
              Text {
                text: modelData.ssid
                color: Theme.text
                elide: Text.ElideRight
                Layout.fillWidth: true
                font { family: "Inter"; pixelSize: Fonts.subtitle; weight: 600 }
              }
              Text {
                text: netCard.connecting ? "Connecting…"
                  : (modelData.saved ? "Saved"
                  : (netCard.expanded ? "Enter password"
                  : (modelData.security && modelData.security !== "--" ? "Secured" : "Open")))
                color: netCard.connecting || modelData.saved || netCard.expanded ? Theme.primary : Theme.text
                opacity: netCard.connecting || modelData.saved || netCard.expanded ? 1 : 0.6
                font { family: "Inter"; pixelSize: Fonts.caption }
              }
            }

            Text {
              visible: modelData.security && modelData.security !== "--"
              text: "󰲛"
              color: Theme.text; opacity: 0.4
              font { family: "JetBrainsMono Nerd Font"; pixelSize: Fonts.iconSmall }
            }
          }

          ColumnLayout {
            visible: netCard.expanded
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
              Layout.fillWidth: true
              height: 38
              radius: 10
              color: Theme.surfaceDim

              TextField {
                id: pwField
                anchors.fill: parent
                anchors.margins: 2
                color: Theme.text
                echoMode: netCard.pwReveal ? TextInput.Normal : TextInput.Password
                placeholderText: "Password"
                placeholderTextColor: Theme.subtext
                background: null
                font { family: "Inter"; pixelSize: Fonts.subtitle }
                focus: netCard.expanded
                Keys.onReturnPressed: netCard.startConnect()
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 10
              GhostButton {
                text: netCard.pwReveal ? "Hide password" : "Show password"
                subdued: true
                onTapped: netCard.pwReveal = !netCard.pwReveal
              }
              Item { Layout.fillWidth: true }
            }

            Text {
              Layout.fillWidth: true
              visible: wifiConnectError.length > 0
              text: wifiConnectError
              color: Theme.danger
              wrapMode: Text.WordWrap
              font { family: "Inter"; pixelSize: Fonts.caption }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 8
              Rectangle {
                Layout.fillWidth: true
                height: 32
                radius: 9
                color: Theme.surface
                Text { anchors.centerIn: parent; text: "Cancel"; color: Theme.text; font { family: "Inter"; pixelSize: Fonts.small; weight: 600 } }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: cancelPassword()
                }
              }
              Rectangle {
                Layout.fillWidth: true
                height: 32
                radius: 9
                color: netCard.connecting ? Theme.surface : Theme.primary
                Text {
                  anchors.centerIn: parent
                  text: netCard.connecting ? "Connecting…" : "Connect"
                  color: netCard.connecting ? Theme.text : Theme.primaryFg
                  font { family: "Inter"; pixelSize: Fonts.small; weight: 700 }
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  enabled: !netCard.connecting
                  onClicked: netCard.startConnect()
                }
              }
            }
          }
        }
      }
    }

    Text {
      Layout.fillWidth: true
      visible: wifiEnabled && sv.visibleNetworks.length === 0
      text: wifiScanning ? "Looking for networks…" : "No networks found"
      color: Theme.text; opacity: 0.45
      horizontalAlignment: Text.AlignHCenter
      Layout.topMargin: 10
      font { family: "Inter"; pixelSize: Fonts.body }
    }

    // ---- 4. SAVED NETWORKS ----
    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: sv.savedList.length > 0 ? 10 : 0
      visible: wifiEnabled && sv.savedList.length > 0
      spacing: 8

      Text {
        text: "Saved"
        color: Theme.text; opacity: 0.7
        font { family: "Inter"; pixelSize: Fonts.body; weight: 700 }
      }
      Item { Layout.fillWidth: true }
      Text {
        text: sv.savedList.length === 1 ? "1 network" : sv.savedList.length + " networks"
        color: Theme.text; opacity: 0.4
        font { family: "Inter"; pixelSize: Fonts.caption }
      }
    }

    Text {
      Layout.fillWidth: true
      Layout.leftMargin: 4
      Layout.rightMargin: 4
      visible: sv.forgetArmed === "" && wifiForgetError.length > 0
      text: wifiForgetError
      color: Theme.danger
      wrapMode: Text.WordWrap
      font { family: "Inter"; pixelSize: Fonts.caption }
    }

    Repeater {
      model: sv.savedList

      delegate: Rectangle {
        id: savedCard
        required property var modelData
        // Sibling of the Repeater, not a child of it - see netCard.
        visible: sv.wifiEnabled
        Layout.fillWidth: true
        Layout.preferredHeight: savedCard.confirming ? confirmCol.implicitHeight + 24 : 48
        radius: 14
        // Out of range is reachable but not actionable, so it sits back a step.
        color: savedCard.confirming
          ? Theme.surface
          : (savedHover.hovered && modelData.inRange ? Theme.surfaceBright : Theme.surface)

        property bool confirming: sv.forgetArmed === modelData.ssid
        readonly property bool reachable: modelData.inRange && !modelData.active

        HoverHandler { id: savedHover; enabled: modelData.inRange }
        MouseArea {
          anchors.fill: parent
          cursorShape: modelData.inRange ? Qt.PointingHandCursor : Qt.ArrowCursor
          enabled: savedCard.reachable
          onClicked: connectToWifi(modelData.ssid, modelData.security || "", "")
        }

        RowLayout {
          anchors.fill: parent
          anchors.margins: 12
          spacing: 12
          visible: !savedCard.confirming
          opacity: modelData.inRange ? 1 : 0.5

          SignalBars {
            strength: modelData.signal
            dimmed: !modelData.inRange
            Layout.alignment: Qt.AlignVCenter
          }

          ColumnLayout {
            spacing: 1
            Layout.fillWidth: true
            Text {
              text: modelData.ssid
              color: Theme.text
              elide: Text.ElideRight
              Layout.fillWidth: true
              font { family: "Inter"; pixelSize: Fonts.subtitle; weight: 600 }
            }
            Text {
              text: modelData.inRange ? "In range · " + modelData.signal + "%" : "Not in range"
              color: Theme.muted
              font { family: "Inter"; pixelSize: Fonts.caption }
            }
          }

          GhostButton {
            text: "Forget"
            armed: true
            onTapped: sv.forgetArmed = savedCard.modelData.ssid
          }
        }

        ColumnLayout {
          id: confirmCol
          visible: savedCard.confirming
          anchors.fill: parent
          anchors.margins: 12
          spacing: 8

          Text {
            text: "Forget " + savedCard.modelData.ssid + "?"
            color: Theme.danger
            elide: Text.ElideRight
            Layout.fillWidth: true
            font { family: "Inter"; pixelSize: Fonts.subtitle; weight: 700 }
          }

          Text {
            text: "The saved password is deleted. You will need it again to reconnect."
            color: Theme.text; opacity: 0.6
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            font { family: "Inter"; pixelSize: Fonts.caption }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
              Layout.fillWidth: true
              height: 32
              radius: 9
              color: Theme.surface
              Text { anchors.centerIn: parent; text: "Cancel"; color: Theme.text; font { family: "Inter"; pixelSize: Fonts.small; weight: 600 } }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: sv.forgetArmed = ""
              }
            }
            Rectangle {
              Layout.fillWidth: true
              height: 32
              radius: 9
              color: Theme.danger
              Text { anchors.centerIn: parent; text: "Forget"; color: Theme.background; font { family: "Inter"; pixelSize: Fonts.small; weight: 700 } }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  forgetWifi(savedCard.modelData.ssid, savedCard.modelData.uuid)
                  sv.forgetArmed = ""
                }
              }
            }
          }
        }
      }
    }

    Item { Layout.preferredHeight: 4 }
  }

  // Switching networks must not leave a password or a QR sitting on screen.
  Connections {
    target: sv
    function onWifiNameChanged() {
      sv.wifiPasswordRevealed = false
      sv.showQr = false
      sv.forgetArmed = ""
    }
  }
}
