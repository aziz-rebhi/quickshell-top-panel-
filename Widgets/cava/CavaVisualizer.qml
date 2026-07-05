import QtQuick
import "../../core"

Row {
    id: visualizer
    property var barHeights: [2, 2, 2, 2]
    property real barMaxHeight: 12

    spacing: 2
    height: barMaxHeight

    Rectangle { width: 2; height: Math.min(visualizer.barMaxHeight, visualizer.barHeights[0]); radius: 1; color: Theme.primary; anchors.bottom: parent.bottom }
    Rectangle { width: 2; height: Math.min(visualizer.barMaxHeight, visualizer.barHeights[1]); radius: 1; color: Theme.primary; anchors.bottom: parent.bottom }
    Rectangle { width: 2; height: Math.min(visualizer.barMaxHeight, visualizer.barHeights[2]); radius: 1; color: Theme.primary; anchors.bottom: parent.bottom }
    Rectangle { width: 2; height: Math.min(visualizer.barMaxHeight, visualizer.barHeights[3]); radius: 1; color: Theme.primary; anchors.bottom: parent.bottom }
}
