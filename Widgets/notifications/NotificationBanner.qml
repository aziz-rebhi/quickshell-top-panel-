import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Services.Notifications
import "../../core"

Rectangle {
  id: root

  property var notification: null
  property var notificationData: null
  readonly property bool expanded: notificationData !== null
  property bool bannerHovered: false

  readonly property real bannerWidth: 480
  readonly property real bannerRadius: 16

  readonly property real bannerHeight: {
    if (!notificationData) return 0;
    var base = 150;
    if (notificationData.image) base += 120 + 6;
    if (notificationData.actions && notificationData.actions.length > 0)
      base += (notificationData.actions.length * 37) - 5;
    if (notificationData.hasInlineReply) base += 40;
    return base;
  }

  function firstActionIdentifier() {
    if (!notificationData || !notificationData.actions || notificationData.actions.length === 0) return "";
    return notificationData.actions[0].identifier;
  }

  function sendReply() {
    if (root.notification && root.notificationData && replyField.text) {
      root.notification.sendInlineReply(replyField.text);
    }
    replyField.text = "";
    root.dismissed(root.notificationData);
  }

  signal dismissed(var notifRef)

  color: bannerHovered ? "#141419" : "#08080be6"
  Behavior on color { ColorAnimation { duration: 150 } }

  layer.enabled: true
  layer.samples: 8
  layer.effect: DropShadow {
    transparentBorder: true
    horizontalOffset: 2
    verticalOffset: 5
    radius: 14
    samples: 29
    color: "#33000000"
  }

  border.width: 1
  border.color: bannerHovered ? "#262632" : "transparent"

  property real dragOffset: 0

  // swaync-style critical treatment: 2px full border instead of left accent bar
  Rectangle {
    visible: root.notificationData && root.notificationData.urgency === NotificationUrgency.Critical
    anchors.fill: parent
    radius: root.bannerRadius
    color: "transparent"
    border.width: 2
    border.color: Theme.subtext
    z: 10
  }

  RowLayout {
    id: content
    anchors.fill: parent
    anchors { leftMargin: 24; rightMargin: 20; topMargin: 18; bottomMargin: 16 }
    spacing: 14
    clip: true

    Item {
      id: iconWrap
      width: 40
      height: 40
      Layout.alignment: Qt.AlignTop
      Layout.topMargin: 2

      Rectangle {
        anchors.fill: parent
        radius: 10
        color: Theme.surfaceVariant
      }

      NotifIcon {
        anchors.centerIn: parent
        iconSize: 22
        appIcon: root.notificationData?.appIcon ?? ""
        appName: root.notificationData?.appName ?? ""
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      spacing: 3

      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
          text: root.notificationData?.appName ?? ""
          color: "#787c99"
          font { family: "JetBrainsMono Nerd Font Propo"; pixelSize: 10; weight: 800; letterSpacing: 0.6 }
          elide: Text.ElideRight
          Layout.fillWidth: true
        }

        Text {
          text: root.notificationData ? Helpers.relTime(root.notificationData.timestamp) : ""
          color: "#787c99"
          font { family: "JetBrainsMono Nerd Font Propo"; pixelSize: 9; weight: 800 }
          opacity: 0.7
        }
      }

      Text {
        text: root.notificationData?.summary ?? ""
        color: root.notificationData
          && root.notificationData.urgency === NotificationUrgency.Critical
          ? Theme.subtext : "#acb0d0"
        font { family: "JetBrainsMono Nerd Font Propo"; pixelSize: 15; weight: 800; letterSpacing: 0.2 }
        lineHeight: 1.2
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        maximumLineCount: 2
      }

      Text {
        text: root.notificationData?.body ?? ""
        visible: text !== ""
        color: "#787c99"
        font { family: "JetBrainsMono Nerd Font Propo"; pixelSize: 11; weight: 400 }
        lineHeight: 1.3
        elide: Text.ElideRight
        Layout.fillWidth: true
        Layout.topMargin: 1
        maximumLineCount: 2
        wrapMode: Text.WordWrap
      }

      Item {
        Layout.fillWidth: true
        Layout.topMargin: 6
        visible: !!root.notificationData?.image
        implicitHeight: 120
        clip: true

        Rectangle {
          anchors.fill: parent
          radius: 10
          color: "#101014"
          border.width: 1
          border.color: "#262632"
          clip: true

          Image {
            anchors.fill: parent
            source: root.notificationData?.image ?? ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
          }
        }
      }

      Rectangle {
        id: progressTrack
        Layout.fillWidth: true
        Layout.topMargin: 6
        height: 4
        radius: 2
        color: "#101014"
        visible: (root.notificationData?.progress ?? -1) >= 0

        Rectangle {
          width: parent.width * Math.min(1, Math.max(0, (root.notificationData?.progress ?? 0) / 100))
          height: parent.height
          radius: 2
          color: Theme.text
        }
      }

      Column {
        id: actionColumn
        visible: root.expanded && root.notificationData?.actions?.length > 0
        Layout.topMargin: 6
        Layout.fillWidth: true
        spacing: 5
        Repeater {
          model: root.notificationData?.actions ?? []

          delegate: Rectangle {
            required property var modelData
            width: actionColumn.width
            implicitHeight: 34
            radius: 16
            color: modelData.identifier === root.firstActionIdentifier()
              ? "#2b2b3a" : (actMouse.containsMouse ? "#1d1d26" : "#101014")
            border.width: modelData.identifier === root.firstActionIdentifier() ? 1 : 0
            border.color: Theme.primary

            scale: actMouse.pressed ? 0.97 : 1.0
            opacity: actMouse.pressed ? 0.9 : 1.0
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 90 } }
            Behavior on color { ColorAnimation { duration: 100 } }

            Text {
              anchors.centerIn: parent
              text: modelData.text || ""
              color: modelData.identifier === root.firstActionIdentifier()
                ? Theme.primaryFg : Theme.text
              font { family: "JetBrainsMono Nerd Font Propo"; pixelSize: 12; weight: 800 }
            }

            MouseArea {
              id: actMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (modelData.invoke) modelData.invoke();
                root.dismissed(root.notificationData);
              }
            }
          }
        }
      }

      RowLayout {
        visible: root.expanded && root.notificationData?.hasInlineReply
        Layout.topMargin: 6
        spacing: 6

        Rectangle {
          Layout.fillWidth: true
          height: 30
          radius: 12
          color: "#101014"
          border.width: replyField.activeFocus ? 1 : 0
          border.color: Theme.text

          TextField {
            id: replyField
            anchors.fill: parent
            anchors.margins: 4
            color: Theme.text
            placeholderText: root.notificationData?.inlineReplyPlaceholder || "Reply…"
            placeholderTextColor: Theme.subtext
            background: null
            font { family: "JetBrainsMono Nerd Font Propo"; pixelSize: 11 }
            Keys.onReturnPressed: sendReply()
          }
        }

        Rectangle {
          implicitWidth: 34
          height: 30
          radius: 12
          color: Theme.primary
          scale: replySend.pressed ? 0.94 : 1.0
          Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

          Text {
            anchors.centerIn: parent
            text: "󱞁"
            color: Theme.primaryFg
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 13 }
          }

          MouseArea {
            id: replySend
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sendReply()
          }
        }
      }
    }

    Text {
      text: "󰅂"
      color: "#acb0d0"
      font { family: "JetBrainsMono Nerd Font"; pixelSize: 16 }
      Layout.alignment: Qt.AlignTop | Qt.AlignRight
      Layout.topMargin: 0

      MouseArea {
        anchors.fill: parent
        anchors.margins: -8
        cursorShape: Qt.PointingHandCursor
        onClicked: root.dismissed(root.notificationData)
      }
    }
  }

  DragHandler {
    id: dragHandler
    target: null
    xAxis { minimum: -bannerWidth; maximum: bannerWidth }
    onActiveChanged: {
      if (!active && Math.abs(root.dragOffset) > 80)
        root.dismissed(root.notificationData);
      if (!active) root.dragOffset = 0;
    }
    onTranslationChanged: (delta) => {
      root.dragOffset = delta.x;
    }
  }

  transform: Translate {
    x: root.dragOffset
  }

  Behavior on dragOffset { NumberAnimation { duration: 150; easing.type: Easing.OutQuart } }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    onContainsMouseChanged: root.bannerHovered = containsMouse
  }

  states: [
    State {
      name: "expanded"
      when: expanded
      PropertyChanges { target: root; width: bannerWidth }
      PropertyChanges { target: root; height: bannerHeight }
      PropertyChanges { target: root; radius: bannerRadius }
      PropertyChanges { target: content; opacity: 1.0 }
    },
    State {
      name: "collapsed"
      when: !expanded
      PropertyChanges { target: root; width: 0 }
      PropertyChanges { target: root; height: 0 }
      PropertyChanges { target: root; radius: 18 }
      PropertyChanges { target: content; opacity: 0.0 }
    }
  ]

  transitions: [
    Transition {
      from: "collapsed"; to: "expanded"
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
      from: "expanded"; to: "collapsed"
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
