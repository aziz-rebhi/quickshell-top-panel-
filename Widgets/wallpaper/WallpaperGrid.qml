import QtQuick
import QtQuick.Layouts
import "../../core"

Item {
  id: root

  property var wallpaperModel: []
  property var wallService: null
  property string selectedWallpaper: ""

  signal wallpaperChosen(string path)

  readonly property int spacing: 10
  readonly property int _idealCols: Math.max(2, Math.floor((flick.width + spacing) / (140 + spacing)))
  readonly property int cols: _idealCols
  readonly property real itemWidth: Math.floor((flick.width - spacing * (cols - 1)) / cols)
  readonly property real itemHeight: Math.round(itemWidth * 9 / 16)

  Flickable {
    id: flick
    anchors.fill: parent
    contentWidth: parent.width
    contentHeight: flow.implicitHeight + 4
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Flow {
      id: flow
      width: parent.width
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: root.spacing
      layoutDirection: Qt.LeftToRight

      Repeater {
        model: root.wallpaperModel

        delegate: Item {
          id: card
          width: root.itemWidth
          height: root.itemHeight

          property bool isHovered: false
          property bool isPressed: false
          property bool isSelected: modelData === root.selectedWallpaper

          Rectangle {
            id: bg
            anchors.fill: parent
            radius: 12
            color: isSelected
              ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
              : "transparent"
            clip: true

            // Thumbnail
            Image {
              id: thumb
              anchors.fill: parent
              anchors.margins: isHovered ? 1 : 2
              source: modelData ? "file://" + modelData : ""
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              sourceSize.width: root.itemWidth * 2
              sourceSize.height: root.itemHeight * 2
              smooth: false
              visible: status === Image.Ready
              Behavior on anchors.margins { NumberAnimation { duration: 100; easing.type: Easing.OutQuart } }
            }

            // Placeholder while loading
            Rectangle {
              anchors.fill: parent
              anchors.margins: isHovered ? 1 : 2
              radius: 9
              color: Theme.surfaceVariant
              visible: thumb.status !== Image.Ready
              Behavior on anchors.margins { NumberAnimation { duration: 100; easing.type: Easing.OutQuart } }
              Text {
                anchors.centerIn: parent
                text: "󰸉"
                color: Theme.subtext
                opacity: 0.35
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 20 }
              }
            }

            // Hover glow border
            Rectangle {
              anchors.fill: parent
              radius: 12
              color: "transparent"
              border.width: isHovered && !isPressed ? 2 : 0
              border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5)
              Behavior on border.width { NumberAnimation { duration: 100 } }
            }

            // Selected highlight border
            Rectangle {
              anchors.fill: parent
              radius: 12
              color: "transparent"
              border.width: isSelected ? 2 : 0
              border.color: Theme.primary
              visible: isSelected
            }

            // Selected check indicator
            Rectangle {
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.margins: 6
              width: 18
              height: 18
              radius: 9
              color: Theme.primary
              visible: isSelected

              Text {
                anchors.centerIn: parent
                text: "✓"
                color: Theme.text
                font { family: "Inter"; pixelSize: 10; weight: Font.Bold }
              }
            }
          }

          // Click + hover scale
          transform: [
            Scale {
              id: cardScale
              origin.x: width / 2
              origin.y: height / 2
              xScale: isPressed ? 0.96 : isHovered ? 1.02 : 1
              yScale: isPressed ? 0.96 : isHovered ? 1.02 : 1
              Behavior on xScale { NumberAnimation { duration: 80; easing.type: Easing.OutCubic } }
              Behavior on yScale { NumberAnimation { duration: 80; easing.type: Easing.OutCubic } }
            }
          ]

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: isHovered = true
            onExited: { isHovered = false; isPressed = false; }
            onPressed: isPressed = true
            onReleased: isPressed = false
            onClicked: {
              root.selectedWallpaper = modelData
              root.wallpaperChosen(modelData)
              if (root.wallService)
                root.wallService.applyWallpaper(modelData)
            }
          }
        }
      }
    }
  }
}
