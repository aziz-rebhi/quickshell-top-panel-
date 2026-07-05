import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"

Rectangle {
  id: appLauncher
  radius: parent?.radius ?? 28
  color: Theme.background
  clip: true
  focus: true

  signal closeRequested()
  property var appService: null
  property bool hovered: false
  property string searchText: ""
  property int selectedIndex: 0

  onVisibleChanged: {
    if (visible) {
      searchText = "";
      selectedIndex = 0;
      Qt.callLater(function() { appLauncher.forceActiveFocus(); });
    }
  }

  function filteredApps() {
    if (!appService || !appService.appModel) return [];
    if (!searchText) return appService.appModel;
    var q = searchText.toLowerCase();
    var result = [];
    for (var i = 0; i < appService.appModel.length; i++) {
      if (appService.appModel[i].name.toLowerCase().indexOf(q) !== -1)
        result.push(appService.appModel[i]);
    }
    return result;
  }

  function launchSelected() {
    var list = appLauncher.filteredApps();
    if (list.length > 0 && appService) {
      var idx = Math.min(appLauncher.selectedIndex, list.length - 1);
      appService.launchApp(list[idx].desktopId);
    }
  }

  Keys.onPressed: (event) => {
    if (event.key === Qt.Key_Escape) {
      appLauncher.closeRequested();
      event.accepted = true;
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      appLauncher.launchSelected();
      appLauncher.closeRequested();
      event.accepted = true;
    } else if (event.key === Qt.Key_Up) {
      var list = appLauncher.filteredApps();
      if (list.length > 0)
        appLauncher.selectedIndex = Math.max(0, appLauncher.selectedIndex - 1);
      event.accepted = true;
    } else if (event.key === Qt.Key_Down) {
      var list2 = appLauncher.filteredApps();
      if (list2.length > 0)
        appLauncher.selectedIndex = Math.min(list2.length - 1, appLauncher.selectedIndex + 1);
      event.accepted = true;
    } else if (event.key === Qt.Key_Backspace) {
      if (searchText.length > 0) {
        searchText = searchText.slice(0, -1);
        selectedIndex = 0;
      }
      event.accepted = true;
    } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32) {
      if (!event.modifiers || event.modifiers === Qt.ShiftModifier) {
        searchText += event.text;
        selectedIndex = 0;
        event.accepted = true;
      }
    }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 12
    spacing: 6

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 32
      radius: 8
      color: Theme.surfaceLight

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 6

        Text {
          text: "󰊯"
          color: Theme.subtext
          font { family: "JetBrainsMono Nerd Font"; pixelSize: 14 }
        }

        Text {
          Layout.fillWidth: true
          color: searchText ? Theme.text : Theme.subtext
          text: searchText || "Search apps…"
          font { family: "Inter"; pixelSize: 12 }
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
        }

        Text {
          visible: searchText.length > 0
          text: "󰁨"
          color: Theme.subtext
          font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              searchText = "";
              selectedIndex = 0;
              appLauncher.forceActiveFocus();
            }
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onClicked: appLauncher.forceActiveFocus()
      }
    }

    ListView {
      id: appList
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      spacing: 2

      model: appLauncher.filteredApps()
      currentIndex: appLauncher.selectedIndex

      onCountChanged: {
        if (appLauncher.selectedIndex >= count)
          appLauncher.selectedIndex = Math.max(0, count - 1);
      }

      delegate: Rectangle {
        width: appList.width
        height: 32
        radius: 6
        color: appList.currentIndex === index ? Theme.surfaceHover : (itemMouse.containsMouse ? Theme.surfaceLight : "transparent")
        Behavior on color { ColorAnimation { duration: 80 } }

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 8
          anchors.rightMargin: 8
          spacing: 8

          Item {
            width: 24; height: 24
            Image {
              id: appIcon
              anchors.fill: parent
              source: {
                var ic = modelData.icon;
                if (!ic || ic.indexOf("/") === -1) return "";
                return "file://" + ic;
              }
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              visible: status === Image.Ready
            }
            Text {
              anchors.centerIn: parent
              text: "󰀻"
              color: appList.currentIndex === index ? Theme.primary : Theme.text
              opacity: appIcon.visible ? 0 : (appList.currentIndex === index ? 1 : 0.5)
              font { family: "JetBrainsMono Nerd Font"; pixelSize: 14 }
            }
          }

          Text {
            text: modelData.name
            color: Theme.text
            elide: Text.ElideRight
            font { family: "Inter"; pixelSize: 12; weight: appList.currentIndex === index ? 600 : 500 }
            Layout.fillWidth: true
          }
        }

        MouseArea {
          id: itemMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: {
            appLauncher.hovered = true;
            appLauncher.selectedIndex = index;
          }
          onExited: appLauncher.hovered = false
          onClicked: {
            appLauncher.selectedIndex = index;
            appLauncher.launchSelected();
          }
        }
      }

      ScrollBar.vertical: ScrollBar {
        width: 4
        policy: ScrollBar.AsNeeded
        contentItem: Rectangle {
          radius: 2
          color: Theme.border
        }
      }
    }
  }
}
