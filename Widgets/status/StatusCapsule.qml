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

    property string wifiName: StatusService.wifi
    property int wifiSignal: StatusService.wifiSignal
    property int batteryPercent: StatusService.battery
    property bool isCharging: StatusService.charging
    property string powerState: StatusService.powerState
    property string networkState: StatusService.networkState
    property string connectionType: StatusService.connType
    property bool isHovered: capsuleMouseArea.containsMouse
    signal clicked()

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
            font { family: "JetBrainsMono Nerd Font"; pixelSize: Fonts.iconSmall }
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
            font { family: "JetBrainsMono Nerd Font"; pixelSize: Fonts.iconSmall }
        }

        Text {
            text: statusCapsule.powerState === "Full" || statusCapsule.isCharging ? "AC" : statusCapsule.batteryPercent + "%"
            color: Theme.text
            font { family: "Inter"; pixelSize: Fonts.small; weight: 700 }
        }
    }
}
