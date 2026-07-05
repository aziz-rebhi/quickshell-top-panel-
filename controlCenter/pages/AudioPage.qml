import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import "../../core"

ScrollView {
  id: sv
  visible: false
  padding: 0
  ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
  ScrollBar.vertical.policy: ScrollBar.AsNeeded
  contentWidth: width

  property var audioSinks: []
  property var audioSink: null
  property var audioSources: []
  property var audioSource: null
  property real audioVolume: 0
  property bool audioMuted: false
  property real audioSourceVolume: 0
  property bool audioSourceMuted: false
  property var volumeIcon: null

  signal backRequested()
  signal setVolume(real vol)
  signal toggleMute()
  signal setAudioSourceVolume(real vol)
  signal toggleAudioSourceMute()
  signal setDefaultSink(var node)
  signal setDefaultSource(var node)

  ColumnLayout {
    width: parent.width
    spacing: 10

    Text {
      text: "Output"
      color: Theme.muted
      font { family: "Inter"; pixelSize: 11; weight: 700 }
      Layout.leftMargin: 4
    }

    Repeater {
      model: audioSinks

      Rectangle {
        required property var modelData
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        radius: 10
        color: modelData === audioSink ? Theme.surfaceHover : Theme.surfaceLight

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 12
          anchors.rightMargin: 12
          spacing: 8

          Text {
            text: modelData === audioSink ? "✓" : "  "
            color: Theme.primary
            font { family: "Inter"; pixelSize: 13; weight: 700 }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
              text: modelData.description || modelData.name || ""
              color: Theme.text
              font { family: "Inter"; pixelSize: 12; weight: modelData === audioSink ? 600 : 400 }
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
            Text {
              text: modelData.nickname || ""
              visible: text !== ""
              color: Theme.subtext
              font { family: "Inter"; pixelSize: 9 }
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: setDefaultSink(modelData)
        }
      }
    }

    IconSlider {
      Layout.fillWidth: true
      iconText: volumeIcon ? volumeIcon(audioVolume, audioMuted) : ""
      value: audioMuted ? 0 : audioVolume
      onMoved: val => setVolume(val)
    }

    Item { Layout.preferredHeight: 8 }

    Text {
      text: "Input"
      color: Theme.muted
      font { family: "Inter"; pixelSize: 11; weight: 700 }
      Layout.leftMargin: 4
    }

    Repeater {
      model: audioSources

      Rectangle {
        required property var modelData
        Layout.fillWidth: true
        Layout.preferredHeight: 40
        radius: 10
        color: modelData === audioSource ? Theme.surfaceHover : Theme.surfaceLight

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 12
          anchors.rightMargin: 12
          spacing: 8

          Text {
            text: modelData === audioSource ? "✓" : "  "
            color: Theme.primary
            font { family: "Inter"; pixelSize: 13; weight: 700 }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
              text: modelData.description || modelData.name || ""
              color: Theme.text
              font { family: "Inter"; pixelSize: 12; weight: modelData === audioSource ? 600 : 400 }
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
            Text {
              text: modelData.nickname || ""
              visible: text !== ""
              color: Theme.subtext
              font { family: "Inter"; pixelSize: 9 }
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: setDefaultSource(modelData)
        }
      }
    }

    IconSlider {
      Layout.fillWidth: true
      iconText: volumeIcon ? volumeIcon(audioSourceVolume, audioSourceMuted) : ""
      value: audioSourceMuted ? 0 : audioSourceVolume
      onMoved: val => setAudioSourceVolume(val)
    }

    Item { Layout.preferredHeight: 4 }
  }
}
