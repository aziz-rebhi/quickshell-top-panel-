import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../Widgets/mode"

/*
 * Performance Control Center — the redesign of the old Mode page.
 *
 * Everything here is real: mode cards describe intent, the Live System
 * section comes from MonitorService's sysfs /proc / nvidia-smi / nbfc probes,
 * the requested-vs-effective split comes from the controller's state.json,
 * and the thermal banner reflects the progressive protection guard the
 * `performance-mode watch` service runs. Nothing is faked; unreadable
 * sensors render as "Unavailable" rather than invented values.
 */

ScrollView {
  id: sv
  padding: 0
  ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
  ScrollBar.vertical.policy: ScrollBar.AsNeeded
  contentWidth: width

  required property var modeSvc

  signal setMode(string mode)
  signal backRequested()

  readonly property var def: modeSvc ? ModeDefs.def(modeSvc.currentMode) : ModeDefs.def("balanced")
  readonly property bool applying: modeSvc ? modeSvc.transitionState === "applying" : false
  readonly property bool done: modeSvc ? modeSvc.transitionState === "done" : false

  function deg(v) { return v > 0 ? v.toFixed(0) + "°C" : "—" }
  function pct(v) { return v >= 0 ? v.toFixed(0) + "%" : "—" }
  function cardW() {
    if (sv.width >= 360) return (sv.width - 16) / 3
    return (sv.width - 8) / 2
  }

  // --- live model rows -----------------------------------------------------
  // These JS arrays are model sources for the Repeaters. Declared as bound
  // property vars on the root so every delegate scope can see them, they stay
  // reactive: QML registers every modeSvc.<prop> access made while the binding
  // evaluates, so the arrays re-materialize (and the UI re-renders) whenever
  // the monitor or the controller state changes.

  property var heroStats: [
    { label: "CPU", main: modeSvc ? pct(modeSvc.monitor.cpuAvailable ? modeSvc.cpuUsage : -1) : "—",
      sub: (modeSvc && modeSvc.cpuFreqMHz > 0) ? modeSvc.cpuFreqMHz + " MHz" : "" },
    { label: "GPU", main: modeSvc ? pct(modeSvc.gpuAvailable ? modeSvc.gpuUsage : -1) : "—",
      sub: modeSvc ? deg(modeSvc.gpuAvailable ? modeSvc.gpuTemp : 0) : "" },
    { label: "FAN", main: modeSvc && modeSvc.fanPct >= 0 ? Math.round(modeSvc.fanPct) + "%"
        : (modeSvc && modeSvc.fanRpm > 0 ? modeSvc.fanRpm + " RPM" : "—"),
      sub: (modeSvc && modeSvc.cpuFreqMHz > 0) ? "" : "" }
  ]

  property var liveRows: [
    {
      label: "CPU", icon: "󰻠",
      main: modeSvc ? pct(modeSvc.monitor.cpuAvailable ? modeSvc.cpuUsage : -1) : "—",
      sub: (modeSvc && modeSvc.cpuFreqMHz > 0 ? modeSvc.cpuFreqMHz + " MHz · " : "")
          + (modeSvc ? deg(modeSvc.monitor.cpuAvailable ? modeSvc.cpuTemp : 0) : "—")
    },
    {
      label: "GPU · NVIDIA", icon: "󰈹",
      main: modeSvc ? pct(modeSvc.gpuAvailable ? modeSvc.gpuUsage : -1) : "—",
      sub: modeSvc && modeSvc.gpuAvailable
          ? deg(modeSvc.gpuTemp) + " · " + modeSvc.vramUsedMB + "/" + modeSvc.vramTotalMB + " MiB"
          : "card off / no data"
    },
    {
      label: "FAN", icon: "󰈐",
      main: modeSvc && modeSvc.fanPct >= 0 ? Math.round(modeSvc.fanPct) + "%"
          : (modeSvc && modeSvc.fanRpm > 0 ? modeSvc.fanRpm + " RPM" : "Unavailable"),
      sub: modeSvc ? (modeSvc.effectiveFanCurve || "curve n/a") : "—"
    },
    {
      label: "POWER", icon: modeSvc && modeSvc.monitor.acPowered ? "󰂄" : "󰁹",
      main: (modeSvc && modeSvc.monitor.acPowered) ? "On AC" : "On battery",
      sub: modeSvc && modeSvc.monitor.batCap >= 0
          ? "Battery " + modeSvc.monitor.batCap + "%" + (modeSvc.monitor.batStatus === "" ? "" : " · " + modeSvc.monitor.batStatus)
          : "battery n/a"
    }
  ]

  // effective readback rows — values bound to the service so they refresh
  // whenever the controller (or the thermal guard) changes the state file
  property var effRows: [
    { label: "Governor", value: modeSvc ? modeSvc.effectiveGovernor : "—",
      warn: modeSvc && modeSvc.thermalActive && modeSvc.effectiveGovernor === "schedutil" },
    { label: "Boost", value: modeSvc ? modeSvc.effectiveBoost : "—",
      warn: modeSvc && modeSvc.thermalActive && modeSvc.effectiveBoost === "0" },
    { label: "NVIDIA power", value: modeSvc ? modeSvc.effectiveNvPm : "—" },
    { label: "persistence", value: modeSvc ? modeSvc.effectivePersistence : "—" },
    { label: "PPD profile", value: modeSvc ? modeSvc.effectivePpd : "—" },
    { label: "Fan curve", value: modeSvc ? modeSvc.effectiveFanCurve : "—" },
    { label: "swappiness", value: modeSvc ? modeSvc.effectiveSwappiness : "—" }
  ]

  function _leverSummary() {
    if (!modeSvc) return ""
    var l = modeSvc.levers
    if (!l) return ""
    var ok = 0, uns = 0, fail = 0, notes = []
    for (var k in l) {
      if (!l.hasOwnProperty(k)) continue
      var st = l[k]["status"]
      if (st === "ok") ok++
      else if (st === "unsupported") { uns++; if (l[k]["note"]) notes.push(l[k]["note"]) }
      else fail++
    }
    var s = ok + "/" + Object.keys(l).length + " levers applied"
    if (uns) s += " · " + uns + " unavailable"
    if (fail) s += " · " + fail + " failed"
    if (notes.length) s += "  (" + notes.join("; ") + ")"
    return s
  }

  ColumnLayout {
    id: col
    width: parent.width
    spacing: 10

    // ---- ERROR (only when a switch failed hard) ----
    Rectangle {
      visible: modeSvc && modeSvc.errorText !== ""
      Layout.fillWidth: true
      radius: 12
      color: Theme.danger
      height: 38
      Text {
        anchors.fill: parent
        anchors.margins: 12
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
        text: "󰅙 " + (modeSvc ? modeSvc.errorText : "")
        color: "#1a0000"
        font { family: "Inter"; pixelSize: 11; weight: 600 }
      }
    }

    // ---- ACTIVE MODE ----
    Rectangle {
      Layout.fillWidth: true
      radius: 18
      color: Theme.surfaceVariant
      border.color: done ? Theme.primary : applying ? Theme.tertiary : "transparent"
      border.width: 1
      implicitHeight: 128

      RowLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 8

          RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
              text: def.icon
              color: Theme.primary
              font { family: "JetBrainsMono Nerd Font"; pixelSize: 26 }
            }
            ColumnLayout {
              Layout.fillWidth: true
              spacing: 1
              Text {
                text: applying ? "APPLYING " + def.name.toUpperCase() + " …" : def.name
                color: Theme.text
                font { family: "Inter"; pixelSize: 17; weight: 700 }
              }
              Text {
                text: def.subtitle
                color: Theme.muted
                font { family: "Inter"; pixelSize: 10; weight: 400 }
                elide: Text.ElideRight
                Layout.fillWidth: true
              }
            }
            Text {
              visible: done
              text: "ACTIVE"
              color: Theme.primary
              font { family: "JetBrainsMono Nerd Font"; pixelSize: 10; weight: 700 }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
              model: def.chips
              delegate: Rectangle {
                required property string modelData
                color: Theme.surfaceBright
                radius: 4
                height: 16
                implicitWidth: pillTxt.implicitWidth + 10
                Text {
                  id: pillTxt
                  anchors.centerIn: parent
                  text: modelData
                  color: Theme.subtext
                  font { family: "Inter"; pixelSize: 9; weight: 600 }
                }
              }
            }
            Item { Layout.fillWidth: true }

            // unsupported lever signal for this mode
            Text {
              visible: modeSvc && modeSvc.leverStatus("GameMode") === "unsupported"
              text: "GameMode unavailable"
              color: Theme.warning
              font { family: "Inter"; pixelSize: 9; weight: 600 }
            }
          }

          Text {
            visible: done && modeSvc
            text: { modeSvc.transitionState; _leverSummary() }
            color: Theme.subtext
            font { family: "Inter"; pixelSize: 9; weight: 500 }
            Layout.fillWidth: true
          }
        }

        // live stats block
        ColumnLayout {
          spacing: 6
          Layout.preferredWidth: 150

          RowLayout {
            spacing: 0
            Layout.fillWidth: true
            Repeater {
              model: heroStats
              delegate: Column {
                required property var modelData
                Layout.fillWidth: true
                spacing: 0
                Text { text: modelData.label; color: Theme.muted; font { family: "Inter"; pixelSize: 8; weight: 700; letterSpacing: 1 } }
                Text { text: modelData.main; color: Theme.text; font { family: "JetBrainsMono Nerd Font"; pixelSize: 16; weight: 600 } }
                Text { text: modelData.sub; color: Theme.subtext; font { family: "JetBrainsMono Nerd Font"; pixelSize: 9 } }
              }
            }
          }
        }
      }
    }

    // ---- THERMAL BANNER ----
    Rectangle {
      visible: modeSvc && modeSvc.thermalActive
      Layout.fillWidth: true
      radius: 12
      color: Qt.rgba(0.40, 0.55, 0.80, 0.16)
      border.color: Theme.warning
      border.width: 1
      implicitHeight: 56
      RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10
        Text {
          text: "⚠"
          color: Theme.warning
          font { family: "Inter"; pixelSize: 15 }
          Layout.alignment: Qt.AlignVCenter
        }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2
          Text {
            text: "THERMAL PROTECTION ACTIVE"
            color: Theme.warning
            font { family: "Inter"; pixelSize: 10; weight: 700; letterSpacing: 1 }
          }
          Text {
            text: {
              if (!modeSvc) return ""
              var n = modeSvc.thermalNote ? " · " + modeSvc.thermalNote : ""
              return "CPU " + deg(modeSvc.cpuTemp) + " ≥ " + modeSvc.thermalThreshold + "°C · effective policy eased · resumes below " +
                     modeSvc.thermalResume + "°C" + n
            }
            color: Theme.subtext
            font { family: "Inter"; pixelSize: 9; weight: 500 }
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }
        }
      }
    }

    // ---- MODES ----
    Text {
      text: "MODES"
      Layout.fillWidth: true
      Layout.leftMargin: 4
      Layout.topMargin: 6
      color: Theme.muted
      font { family: "Inter"; pixelSize: 10; weight: 700; letterSpacing: 1.2 }
    }

    Flow {
      Layout.fillWidth: true
      Layout.preferredHeight: Math.ceil(ModeDefs.keys.length / (sv.width >= 360 ? 3 : 2)) * (96 + 8)
      spacing: 8
      Repeater {
        model: ModeDefs.keys
        delegate: Rectangle {
          required property string modelData
          property var d: ModeDefs.def(modelData)
          property bool active: modeSvc && modeSvc.currentMode === modelData
          width: sv.cardW()
          height: 96
          radius: 14
          color: active ? Theme.surfaceBright : Theme.surfaceVariant
          border.color: active ? Theme.primary : "transparent"
          border.width: 1

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sv.setMode(d.key)
          }

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6

            RowLayout {
              Layout.fillWidth: true
              spacing: 6
              Text { text: d.icon; color: active ? Theme.primary : Theme.muted; font { family: "JetBrainsMono Nerd Font"; pixelSize: 16 } }
              Text {
                text: d.name
                color: Theme.text
                font { family: "Inter"; pixelSize: 12; weight: 700 }
                Layout.fillWidth: true
              }
              Text {
                visible: active
                text: "●"
                color: Theme.primary
                font { family: "Inter"; pixelSize: 8 }
              }
            }

            Text {
              text: d.tag
              color: Theme.muted
              font { family: "Inter"; pixelSize: 9; weight: 500 }
              Layout.fillWidth: true
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 4
              Repeater {
                model: d.chips
                delegate: Rectangle {
                  required property string modelData
                  color: Theme.surfaceBright
                  radius: 4
                  height: 16
                  implicitWidth: pillTxt.implicitWidth + 10
                  Text {
                    id: pillTxt
                    anchors.centerIn: parent
                    text: modelData
                    color: Theme.subtext
                    font { family: "Inter"; pixelSize: 9; weight: 600 }
                  }
                }
              }
              Item { Layout.fillWidth: true }
            }
          }
        }
      }
    }

    // ---- LIVE SYSTEM ----
    Text {
      text: "LIVE SYSTEM"
      Layout.fillWidth: true
      Layout.leftMargin: 4
      Layout.topMargin: 6
      color: Theme.muted
      font { family: "Inter"; pixelSize: 10; weight: 700; letterSpacing: 1.2 }
    }

    Grid {
      columns: 2
      columnSpacing: 8
      rowSpacing: 8
      Layout.fillWidth: true

      Repeater {
        model: liveRows
        delegate: Rectangle {
          required property var modelData
          implicitHeight: 68
          radius: 12
          color: Theme.surfaceVariant

          RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10
            Text { text: modelData.icon; color: Theme.muted; font { family: "JetBrainsMono Nerd Font"; pixelSize: 16 } }
            ColumnLayout {
              Layout.fillWidth: true
              spacing: 1
              Text { text: modelData.label; color: Theme.muted; font { family: "Inter"; pixelSize: 8; weight: 700; letterSpacing: 1.2 } }
              Text { text: modelData.main; color: Theme.text; font { family: "JetBrainsMono Nerd Font"; pixelSize: 14; weight: 600 } }
              Text {
                text: modelData.sub === "" ? "—" : modelData.sub
                color: Theme.subtext
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 9 }
                elide: Text.ElideRight
                Layout.fillWidth: true
              }
            }
          }
        }
      }
    }

    // ---- SYSTEM PROFILE ----
    Text {
      text: "SYSTEM PROFILE"
      Layout.fillWidth: true
      Layout.leftMargin: 4
      Layout.topMargin: 6
      color: Theme.muted
      font { family: "Inter"; pixelSize: 10; weight: 700; letterSpacing: 1.2 }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.leftMargin: 12
      Layout.rightMargin: 12
      implicitHeight: 44
      color: "transparent"

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 5
        radius: 3
        color: Theme.outlineVariant
      }

      Repeater {
        model: ModeDefs.data
        delegate: Rectangle {
          required property var modelData
          property real progX: modelData.profile / 100 * parent.parent.width
          width: 1
          height: 5
          color: Theme.outline
          x: progX
          y: parent.verticalCenter - 2.5
        }
      }

      // active marker
      Rectangle {
        property real px: (def.profile / 100) * parent.width
        x: px - 3
        y: parent.height / 2 - 8
        width: 6
        height: 6
        radius: 3
        color: Theme.primary
        Text {
          anchors.top: parent.bottom
          anchors.topMargin: 4
          anchors.horizontalCenter: parent.horizontalCenter
          text: "▲ " + def.name
          color: Theme.primary
          font { family: "Inter"; pixelSize: 8; weight: 700 }
        }
      }
    }

    // ---- MODE CONFIGURATION / EFFECTIVE NOW ----
    RowLayout {
      Layout.fillWidth: true
      spacing: 8
      Layout.topMargin: 2

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 158
        radius: 14
        color: Theme.surfaceVariant
        ColumnLayout {
          anchors.fill: parent
          anchors.margins: 12
          spacing: 6
          Text {
            text: "MODE CONFIGURATION"
            color: Theme.muted
            font { family: "Inter"; pixelSize: 8; weight: 700; letterSpacing: 1.2 }
          }
          Repeater {
            model: def.config
            delegate: RowLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: 8
              Text {
                text: modelData[0]
                color: Theme.subtext
                font { family: "Inter"; pixelSize: 9 }
                Layout.fillWidth: true
              }
              Text {
                text: modelData[1]
                color: Theme.text
                font { family: "Inter"; pixelSize: 9; weight: 600 }
                horizontalAlignment: Text.AlignRight
              }
            }
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 158
        radius: 14
        color: Theme.surfaceVariant
        ColumnLayout {
          anchors.fill: parent
          anchors.margins: 12
          spacing: 6
          Text {
            text: "EFFECTIVE NOW"
            color: Theme.warning
            font { family: "Inter"; pixelSize: 8; weight: 700; letterSpacing: 1.2 }
          }
          Repeater {
            model: effRows
            delegate: RowLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: 8
              Text {
                text: modelData.label
                color: Theme.subtext
                font { family: "Inter"; pixelSize: 9 }
                Layout.fillWidth: true
              }
              Text {
                text: modelData.value === "" || modelData.value === undefined ? "—" : modelData.value
                color: modelData.warn ? Theme.warning : Theme.text
                font { family: "Inter"; pixelSize: 9; weight: 600 }
                horizontalAlignment: Text.AlignRight
              }
            }
          }
        }
      }
    }

    // ---- THERMALS ----
    Text {
      text: "THERMALS"
      Layout.fillWidth: true
      Layout.leftMargin: 4
      Layout.topMargin: 6
      color: Theme.muted
      font { family: "Inter"; pixelSize: 10; weight: 700; letterSpacing: 1.2 }
    }

    Rectangle {
      Layout.fillWidth: true
      radius: 14
      color: Theme.surfaceVariant
      implicitHeight: 108
      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 6
        RowLayout {
          Layout.fillWidth: true
          spacing: 10
          Text {
            text: "CPU"
            color: Theme.subtext
            font { family: "Inter"; pixelSize: 9 }
            Layout.preferredWidth: 60
          }
          Text {
            text: deg(modeSvc ? modeSvc.cpuTemp : 0)
            color: modeSvc && modeSvc.thermalActive ? Theme.warning : Theme.text
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 12; weight: 600 }
            Layout.preferredWidth: 70
          }
          Text {
            text: modeSvc && modeSvc.thermalActive ? "protected — effective policy eased, resumes below " + modeSvc.thermalResume + "°C"
                : "normal — progressive guard eases boost above " + (modeSvc ? modeSvc.thermalThreshold : 88) + "°C"
            color: Theme.subtext
            font { family: "Inter"; pixelSize: 9 }
            Layout.fillWidth: true
          }
        }
        RowLayout {
          Layout.fillWidth: true
          spacing: 10
          Text {
            text: "GPU"
            color: Theme.subtext
            font { family: "Inter"; pixelSize: 9 }
            Layout.preferredWidth: 60
          }
          Text {
            text: modeSvc && modeSvc.gpuAvailable ? deg(modeSvc.gpuTemp) : "Unavailable"
            color: Theme.text
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 12; weight: 600 }
            Layout.preferredWidth: 70
          }
          Text {
            text: modeSvc && modeSvc.gpuName ? modeSvc.gpuName : ""
            color: Theme.subtext
            font { family: "Inter"; pixelSize: 9 }
            Layout.fillWidth: true
          }
        }
        RowLayout {
          Layout.fillWidth: true
          spacing: 10
          Text {
            text: "FAN"
            color: Theme.subtext
            font { family: "Inter"; pixelSize: 9 }
            Layout.preferredWidth: 60
          }
          Text {
            text: (modeSvc && modeSvc.fanPct >= 0 ? Math.round(modeSvc.fanPct) + "%"
                : modeSvc && modeSvc.fanRpm > 0 ? modeSvc.fanRpm + " RPM" : "Unavailable")
            color: Theme.text
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 12; weight: 600 }
            Layout.preferredWidth: 70
          }
          Text {
            text: "curve: " + (modeSvc ? modeSvc.effectiveFanCurve || "—" : "—")
            color: Theme.subtext
            font { family: "Inter"; pixelSize: 9 }
            Layout.fillWidth: true
          }
        }
      }
    }

    // ---- FOOTER ----
    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: 2
      Layout.leftMargin: 4
      Layout.rightMargin: 4
      Layout.bottomMargin: 6
      spacing: 8

      Text {
        text: (modeSvc ? modeSvc.currentMode.toUpperCase() : "—") + " · changed " + (modeSvc ? modeSvc.lastChangeString : "—")
        color: Theme.muted
        font { family: "Inter"; pixelSize: 8; weight: 600; letterSpacing: 1 }
      }
      Item { Layout.fillWidth: true }
      Text {
        text: modeSvc && modeSvc.thermalActive ? "PROTECTION ACTIVE (" + modeSvc.thermalStage.toUpperCase() + ")"
            : "PROTECTION IDLE · resume " + (modeSvc ? modeSvc.thermalResume : 82) + "°C"
        color: modeSvc && modeSvc.thermalActive ? Theme.warning : Theme.muted
        font { family: "Inter"; pixelSize: 8; weight: 600; letterSpacing: 1 }
      }
    }

    // ---- model names strip ----
    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: 4
      Layout.rightMargin: 4
      Layout.bottomMargin: 8
      spacing: 8
      Text {
        text: (modeSvc && modeSvc.monitor.cpuName ? modeSvc.monitor.cpuName : "CPU").replace(/\(R\)/g, "").replace(/with Radeon Graphics/g, "")
        color: Theme.subtext
        font { family: "Inter"; pixelSize: 8 }
        elide: Text.ElideRight
        Layout.fillWidth: true
      }
      Text {
        text: (modeSvc && modeSvc.monitor.gpuName ? modeSvc.monitor.gpuName : "GPU not detected")
        color: Theme.subtext
        font { family: "Inter"; pixelSize: 8 }
        Layout.alignment: Qt.AlignRight
      }
    }
  }
}