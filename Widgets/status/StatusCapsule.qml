import QtQuick
import QtQuick.Layouts

import "../../core"

Rectangle {
    id: statusCapsule
    color: capsuleMouseArea.containsMouse ? Theme.surfaceHover : Theme.surface
    radius: 12
    height: 24
    width: layout.implicitWidth + 24

    Behavior on color { ColorAnimation { duration: 150 } }

    property string wifiName: status.wifi
    property int wifiSignal: status.wifiSignal
    property int batteryPercent: status.battery
    property bool isCharging: status.charging
    property string powerState: status.powerState
    property string networkState: status.networkState
    property string connectionType: status.connType
    property bool isHovered: capsuleMouseArea.containsMouse
    signal clicked()

    StatusService {
        id: status
    }

    MouseArea {
        id: capsuleMouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: statusCapsule.clicked()
    }

    RowLayout {
        id: layout
        anchors.centerIn: parent
        spacing: 10

        Text {
            text: statusCapsule.networkState === "Disconnected" ? "󰤭"
                : statusCapsule.connectionType === "wired" ? "󰌚"
                : statusCapsule.wifiSignal > 75 ? "󰤨"
                : statusCapsule.wifiSignal > 50 ? "󰤥"
                : statusCapsule.wifiSignal > 25 ? "󰤢"
                : "󰤟"
            color: statusCapsule.networkState === "Disconnected" ? Theme.subtext : Theme.primary
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 13 }
        }

        Text {
            text: {
                if (statusCapsule.powerState === "Full") return "󰂅";
                if (statusCapsule.isCharging) return "󰂄";
                var p = statusCapsule.batteryPercent;
                if (p > 80) return "󰁹";
                if (p > 50) return "󰂀";
                if (p > 20) return "󰁽";
                return "󰁺";
            }
            color: statusCapsule.batteryPercent > 20 ? Theme.primary : Theme.error
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 13 }
        }

        Text {
            text: statusCapsule.powerState === "Full" || statusCapsule.isCharging ? "AC" : statusCapsule.batteryPercent + "%"
            color: Theme.text
            font { family: "Inter"; pixelSize: 11; weight: 700 }
        }
    }
}
