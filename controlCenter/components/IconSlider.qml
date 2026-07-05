import QtQuick
import QtQuick.Layouts
import "../../core"

Item {
  id: slider
  property string iconText: ""
  property real value: 0
  signal moved(real val)

  Layout.fillWidth: true
  height: 40

  Rectangle {
    id: track
    anchors.fill: parent
    radius: 20
    color: Theme.surface

    Rectangle {
      width: Math.max(40, parent.width * slider.value)
      height: parent.height
      radius: 20
      color: Theme.primary
      Behavior on width { enabled: !drag.pressed; NumberAnimation { duration: 100 } }
    }

    RowLayout {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: 14
      spacing: 0
      Text {
        text: slider.iconText
        color: Theme.primaryFg
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 15 }
      }
    }

    MouseArea {
      id: drag
      anchors.fill: parent
      onPressed: mouse => slider.moved(mouse.x / width)
      onPositionChanged: mouse => { if (pressed) slider.moved(mouse.x / width) }
    }
  }
}
