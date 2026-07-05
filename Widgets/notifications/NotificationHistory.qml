import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.Notifications
import "../../core"

Rectangle {
  id: historyRoot

  property var storedNotifications: []
  property var expandedGroups: ({})

  signal dismissNotif(var notifRef)
  signal clearAll()

  radius: 16
  color: Theme.surface
  clip: true

  function buildGroups(arr) {
    if (!arr || arr.length === 0) return [];
    var groups = [];
    var current = null;
    for (var i = 0; i < arr.length; i++) {
      var item = arr[i];
      var app = item.appName || "Unknown";
      if (!current || current.appName !== app) {
        current = { appName: app, appIcon: item.appIcon, items: [] };
        groups.push(current);
      }
      current.items.push(item);
    }
    return groups;
  }

  function toggleGroup(appName) {
    var key = appName || "Unknown";
    var copy = {};
    for (var k in historyRoot.expandedGroups)
      copy[k] = historyRoot.expandedGroups[k];
    if (copy[key])
      copy[key] = false;
    else
      copy[key] = true;
    historyRoot.expandedGroups = copy;
  }

  function isGroupExpanded(appName) {
    return historyRoot.expandedGroups[appName || "Unknown"] === true;
  }

  function relTime(ts) {
    if (!ts) return "";
    var diff = Date.now() - ts;
    if (diff < 60000) return "now";
    if (diff < 3600000) return Math.floor(diff / 60000) + "m ago";
    if (diff < 86400000) return Math.floor(diff / 3600000) + "h ago";
    var days = Math.floor(diff / 86400000);
    return days === 1 ? "Yesterday" : days + "d ago";
  }

  readonly property var groupedNotifs: buildGroups(storedNotifications)

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 14
    spacing: 10

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      Text {
        text: "Notifications"
        color: Theme.text
        opacity: 0.7
        font { family: "Inter"; pixelSize: 11; weight: 700 }
        Layout.fillWidth: true
      }

      Text {
        text: "Clear all"
        color: Theme.primary
        font { family: "Inter"; pixelSize: 11; weight: 600 }
        visible: (historyRoot.storedNotifications?.length ?? 0) > 1

        MouseArea {
          anchors.fill: parent
          anchors.margins: -6
          cursorShape: Qt.PointingHandCursor
          onClicked: historyRoot.clearAll()
        }
      }
    }

    ScrollView {
      id: notifScroll
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: (storedNotifications?.length ?? 0) > 0
      clip: true

      Column {
        spacing: 8
        width: notifScroll.availableWidth

        Repeater {
          model: historyRoot.groupedNotifs

          delegate: Rectangle {
            id: groupCard
            required property var modelData
            width: parent.width
            implicitHeight: groupBody.visible ? groupBody.implicitHeight + headerRow.implicitHeight + 24 + 8 : headerRow.implicitHeight + 24
            radius: 14
            color: Theme.surfaceLight

            property string groupAppName: modelData.appName
            property bool groupExpanded: historyRoot.isGroupExpanded(groupAppName)

            ColumnLayout {
              anchors.fill: parent
              spacing: 0

              RowLayout {
                id: headerRow
                Layout.fillWidth: true
                Layout.margins: 14
                spacing: 8

                NotifIcon {
                  iconSize: 20
                  appIcon: modelData.appIcon || ""
                  appName: modelData.appName || ""
                }

                Text {
                  text: modelData.appName || "Unknown"
                  color: Theme.text
                  font { family: "Inter"; pixelSize: 12; weight: 700 }
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }

                Rectangle {
                  implicitWidth: countText.implicitWidth + 10
                  implicitHeight: 18
                  radius: 9
                  color: Theme.surface
                  visible: modelData.items.length > 1

                  Text {
                    id: countText
                    anchors.centerIn: parent
                    text: modelData.items.length
                    color: Theme.muted
                    font { family: "Inter"; pixelSize: 10; weight: 600 }
                  }
                }

                Text {
                  text: groupCard.groupExpanded ? "" : ""
                  color: Theme.subtext
                  font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: historyRoot.toggleGroup(groupCard.groupAppName)
                }
              }

              Column {
                id: groupBody
                visible: groupCard.groupExpanded
                Layout.fillWidth: true
                spacing: 6
                Layout.bottomMargin: 8

                Repeater {
                  model: modelData.items

                  delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    implicitHeight: notifRow.implicitHeight + 16
                    radius: 10
                    color: "transparent"

                    RowLayout {
                      id: notifRow
                      anchors.fill: parent
                      anchors.margins: 14
                      spacing: 8

                      Rectangle {
                        visible: modelData.urgency === NotificationUrgency.Critical
                        width: 3
                        Layout.fillHeight: true
                        radius: 2
                        color: Theme.error
                        Layout.maximumHeight: parent.height
                      }

                      ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        RowLayout {
                          Layout.fillWidth: true
                          spacing: 6

                          Text {
                            text: modelData.summary || ""
                            color: modelData.urgency === NotificationUrgency.Critical
                              ? Theme.error : Theme.text
                            font { family: "Inter"; pixelSize: 12; weight: 600 }
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                          }

                          Text {
                            text: historyRoot.relTime(modelData.timestamp)
                            color: Theme.muted
                            font { family: "Inter"; pixelSize: 9; weight: 500 }
                            opacity: 0.6
                          }
                        }

                        Text {
                          text: modelData.body || ""
                          visible: text !== ""
                          color: Theme.subtext
                          font { family: "Inter"; pixelSize: 10 }
                          Layout.fillWidth: true
                          Layout.topMargin: 1
                          maximumLineCount: 2
                          wrapMode: Text.WordWrap
                        }

                        Flow {
                          visible: modelData.actions && modelData.actions.length > 0
                          Layout.topMargin: 4
                          spacing: 6

                          Repeater {
                            model: modelData.actions

                            delegate: Rectangle {
                              required property var modelData
                              implicitWidth: actText.implicitWidth + 12
                              implicitHeight: 20
                              radius: 10
                              color: Theme.surface

                              Text {
                                id: actText
                                anchors.centerIn: parent
                                text: modelData.text || ""
                                color: Theme.primary
                                font { family: "Inter"; pixelSize: 9; weight: 600 }
                              }

                              MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                  if (modelData.invoke) modelData.invoke();
                                }
                              }
                            }
                          }
                        }
                      }

                      Text {
                        Layout.alignment: Qt.AlignTop
                        text: "✕"
                        color: Theme.subtext
                        font { family: "Inter"; pixelSize: 11 }
                        MouseArea {
                          anchors.fill: parent
                          anchors.margins: -6
                          cursorShape: Qt.PointingHandCursor
                          onClicked: historyRoot.dismissNotif(modelData)
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
