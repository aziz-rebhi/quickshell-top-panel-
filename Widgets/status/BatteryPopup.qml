import QtQuick
import QtQuick.Layouts
import "../../core"

Rectangle {
  id: popup

  property int displayMs: 4000
  property bool shown: state === "shown"

  state: "hidden"
  states: [
    State { name: "hidden"; PropertyChanges { target: popup; opacity: 0 } },
    State { name: "shown"; PropertyChanges { target: popup; opacity: 1 } }
  ]
  transitions: [
    Transition {
      from: "hidden"; to: "shown"
      NumberAnimation { property: "opacity"; duration: 200; easing.type: Easing.OutCubic }
    },
    Transition {
      from: "shown"; to: "hidden"
      NumberAnimation { property: "opacity"; duration: 250; easing.type: Easing.InCubic }
    }
  ]

  onStateChanged: {
    if (popup.state === "shown") showTimer.restart()
    else if (popup.state === "hidden") showTimer.stop()
  }
  Timer {
    id: showTimer
    interval: popup.displayMs
    onTriggered: popup.state = "hidden"
  }

  radius: 14
  color: Theme.background
  border.width: 1
  border.color: Theme.outlineVariant
  implicitHeight: 40
  visible: opacity > 0

  RowLayout {
    anchors.centerIn: parent
    spacing: 10
    anchors.leftMargin: 16
    anchors.rightMargin: 16

    Text {
      id: iconText
      text: ""
      color: Theme.text
      font { family: "JetBrainsMono Nerd Font"; pixelSize: 18 }
    }

    Text {
      id: mainText
      text: ""
      color: Theme.text
      font { family: "Inter"; pixelSize: 13; weight: 700 }
    }

    Text {
      id: subText
      text: ""
      color: Theme.subtext
      font { family: "Inter"; pixelSize: 12; weight: 500 }
    }
  }

  function notify(kind) {
    var pct = StatusService.battery
    if (kind === "low30") {
      iconText.text = "󰁺"; iconText.color = Theme.error;
      mainText.text = "Battery low"; mainText.color = Theme.text;
      subText.text = pct + "%"; subText.color = Theme.error;
    } else if (kind === "low15") {
      iconText.text = "󰂎"; iconText.color = Theme.error;
      mainText.text = "Battery critical"; mainText.color = Theme.error;
      subText.text = pct + "%"; subText.color = Theme.error;
    } else if (kind === "charging") {
      iconText.text = "󱟩"; iconText.color = Theme.success;
      mainText.text = "Charging"; mainText.color = Theme.text;
      subText.text = pct + "%"; subText.color = Theme.subtext;
    } else if (kind === "unplug") {
      iconText.text = "󰂑"; iconText.color = Theme.warning;
      mainText.text = "On battery"; mainText.color = Theme.text;
      subText.text = pct + "%"; subText.color = Theme.subtext;
    }
    popup.state = "shown";
    showTimer.restart();
  }
}
