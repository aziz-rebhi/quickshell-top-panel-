import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"

Rectangle {
  id: root

  property string promptText: ""
  property string fifoPath: ""
  readonly property bool active: promptText.length > 0

  onActiveChanged: {
    if (active) {
      pwField.forceActiveFocus();
      focusTimer.restart();
    }
  }

  Timer {
    id: focusTimer
    interval: 100
    repeat: false
    onTriggered: pwField.forceActiveFocus()
  }

  signal submitted(string password)
  signal cancelled()

  readonly property real bannerWidth: 480
  readonly property real bannerHeight: 200
  readonly property real bannerRadius: 28

  color: Theme.background
  clip: true

  layer.enabled: true
  layer.samples: 4

  ColumnLayout {
    id: content
    anchors.fill: parent
    anchors.margins: 20
    spacing: 10

    Text {
      text: root.promptText
      color: Theme.text
      font { family: "Inter"; pixelSize: 13; weight: 600 }
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
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
        focus: root.active
        Keys.onReturnPressed: submit()
        Keys.onEscapePressed: root.cancelled()
      }
    }

    RowLayout {
      Layout.fillWidth: true
      CheckBox {
        id: revealBtn
        text: "Show password"
        contentItem: Text {
          text: revealBtn.text
          color: Theme.text
          opacity: 0.7
          leftPadding: revealBtn.indicator.width + 6
          font { family: "Inter"; pixelSize: 11 }
        }
      }
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
        Text {
          anchors.centerIn: parent
          text: "Cancel"
          color: Theme.text
          font { family: "Inter"; pixelSize: 12; weight: 600 }
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.cancelled()
        }
      }

      Rectangle {
        Layout.fillWidth: true
        height: 36
        radius: 10
        color: Theme.primary
        Text {
          anchors.centerIn: parent
          text: "Submit"
          color: Theme.primaryFg
          font { family: "Inter"; pixelSize: 12; weight: 700 }
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: submit()
        }
      }
    }
  }

  states: [
    State {
      name: "expanded"
      when: active
      PropertyChanges { target: root; width: bannerWidth }
      PropertyChanges { target: root; height: bannerHeight }
      PropertyChanges { target: root; radius: bannerRadius }
      PropertyChanges { target: content; opacity: 1.0 }
    },
    State {
      name: "collapsed"
      when: !active
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

  function submit() {
    console.log("askpass: dialog submit, pw len=" + pwField.text.length);
    root.submitted(pwField.text);
    pwField.text = "";
  }
}
