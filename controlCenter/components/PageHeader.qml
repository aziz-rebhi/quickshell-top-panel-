import QtQuick
import QtQuick.Layouts
import "../../core"

RowLayout {
  property string title: ""
  signal backTapped()

  Layout.fillWidth: true
  spacing: 8

  Text {
    text: "󰅁"
    color: Theme.text
    font { family: "JetBrainsMono Nerd Font"; pixelSize: 18 }
    MouseArea {
      anchors.fill: parent
      anchors.margins: -8
      cursorShape: Qt.PointingHandCursor
      onClicked: parent.parent.backTapped()
    }
  }
  Text {
    text: parent.title
    color: Theme.text
    font { family: "Inter"; pixelSize: 15; weight: 700 }
    Layout.fillWidth: true
  }
}
