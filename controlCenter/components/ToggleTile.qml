import QtQuick
import QtQuick.Layouts
import "../../core"

Rectangle {
  id: tile
  property string iconText: ""
  property string label: ""
  property string sublabel: ""
  property bool active: false
  property bool expandable: false
  signal tapped()
  signal expandTapped()

  Layout.fillWidth: true
  Layout.preferredHeight: 56
  radius: 16
  color: active ? Theme.primary : Theme.surface

  Behavior on color { ColorAnimation { duration: 150 } }

  RowLayout {
    anchors.fill: parent
    anchors.margins: 12
    spacing: 10

    Rectangle {
      width: 32; height: 32; radius: 16
      color: tile.active ? Theme.primaryFg : Theme.background

      Text {
        anchors.centerIn: parent
        text: tile.iconText
        color: tile.active ? Theme.text : Theme.primary
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 14 }
      }
    }
    ColumnLayout {
      spacing: 0
      Layout.fillWidth: true
      Text {
        text: tile.label
        color: tile.active ? Theme.background : Theme.text
        elide: Text.ElideRight
        Layout.fillWidth: true
        font { family: "Inter"; pixelSize: 13; weight: 700 }
      }
      Text {
        text: tile.sublabel
        color: tile.active ? Theme.background : Theme.text
        opacity: 0.7
        elide: Text.ElideRight
        Layout.fillWidth: true
        font { family: "Inter"; pixelSize: 10 }
      }
    }
    Text {
      visible: tile.expandable
      text: "󰅂"
      color: tile.active ? Theme.background : Theme.text
      opacity: 0.6
      font { family: "JetBrainsMono Nerd Font"; pixelSize: 14 }
    }
  }

  MouseArea {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: tile.expandable ? parent.width * 0.72 : parent.width
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    onClicked: tile.tapped()
  }

  MouseArea {
    visible: tile.expandable
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: parent.width * 0.28
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    onClicked: tile.expandTapped()
  }
}
