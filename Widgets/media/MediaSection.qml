import QtQuick
import QtQuick.Layouts
import "../../core"

RowLayout {
    id: mediaSection
    spacing: 8

    property string trackTitle: "No Media"
    property string trackArtist: "Unknown Artist"
    property string trackArt: ""
    property string mediaState: "Idle"
    property var barHeights: [2, 2, 2, 2]

    Rectangle {
        width: 44
        height: 44
        radius: 10
        color: Theme.surfaceLight
        clip: true

        Image {
            anchors.fill: parent
            source: mediaSection.trackArt || ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 88
            sourceSize.height: 88

            Rectangle {
                anchors.fill: parent
                color: Theme.surfaceLight
                visible: parent.status !== Image.Ready

                Text {
                    anchors.centerIn: parent
                    text: "󰎆"
                    color: Theme.primary
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 18 }
                }
            }
        }
    }

    ColumnLayout {
        spacing: 1
        Layout.alignment: Qt.AlignVCenter

        RowLayout {
            spacing: 6

            Row {
                spacing: 2
                height: 10
                visible: mediaSection.mediaState === "Playing"
                Layout.alignment: Qt.AlignVCenter

                Rectangle { width: 2; height: Math.min(10, mediaSection.barHeights[0]); radius: 0.5; color: Theme.primary; anchors.bottom: parent.bottom }
                Rectangle { width: 2; height: Math.min(10, mediaSection.barHeights[1]); radius: 0.5; color: Theme.primary; anchors.bottom: parent.bottom }
                Rectangle { width: 2; height: Math.min(10, mediaSection.barHeights[2]); radius: 0.5; color: Theme.primary; anchors.bottom: parent.bottom }
                Rectangle { width: 2; height: Math.min(10, mediaSection.barHeights[3]); radius: 0.5; color: Theme.primary; anchors.bottom: parent.bottom }
            }

            Text {
                text: mediaSection.trackTitle
                color: mediaSection.mediaState === "Idle" ? Theme.subtext : Theme.text
                opacity: mediaSection.mediaState === "Idle" ? 0.6 : 1.0
                elide: Text.ElideRight
                Layout.maximumWidth: 120
                font { family: "Inter"; pixelSize: 12; weight: 500 }
            }
        }

        Text {
            text: mediaSection.mediaState === "Idle" ? "" : mediaSection.trackArtist
            color: Theme.text
            opacity: 0.5
            elide: Text.ElideRight
            Layout.maximumWidth: 120
            font { family: "Inter"; pixelSize: 10 }
        }
    }
}
