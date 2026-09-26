import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../core"
import "../../Widgets/mode"

/*
 * Performance Control Center.
 *
 * Everything here is real: mode cards describe intent, the live strip comes
 * from MonitorService's discovered sysfs /proc / nvidia-smi / nbfc probes, the
 * requested-vs-effective split comes from the controller's state.json, and the
 * thermal banner reflects the progressive protection guard the
 * `performance-mode watch` service runs. Nothing is faked; unreadable sensors
 * render as "Unavailable" rather than invented values.
 *
 * Layout budget: the panel viewport is 560px tall, so the common path (no
 * thermal event, details collapsed) is built to fit without scrolling. The
 * hierarchy is action-first — active mode, then the mode cards, then the
 * readings, then the levers — with everything explanatory (policy readback,
 * diagnostics, history) behind a disclosure header. Sections that used to
 * repeat the same numbers in three places (hero stats + live grid + THERMALS
 * card) were merged: every reading is still on screen, just once.
 *
 * Page visibility is published back to ModeService (pageActive) so neither the
 * state.json poll nor the hardware probe runs at full rate behind a closed
 * panel.
 */

ScrollView {
  id: sv
  padding: 0
  ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
  ScrollBar.vertical.policy: ScrollBar.AsNeeded
  contentWidth: width
  // The Column sums its children's heights, and every section declares an
  // explicit one, so this is the page's real height and stays right as sections
  // appear and collapse.
  contentHeight: col.implicitHeight

  required property var modeSvc
  // Set by ControlCenter: true only while this page is actually on screen.
  property bool pageActive: false

  signal setMode(string mode)
  signal backRequested()

  onPageActiveChanged: if (modeSvc) modeSvc.pageActive = pageActive
  Component.onCompleted: if (modeSvc) modeSvc.pageActive = pageActive

  // Thin usage/level meter. value < 0 means "no reading" and renders empty —
  // an unavailable sensor never gets a bar that looks like zero.
  component Meter: Rectangle {
    id: track
    property real value: -1
    property real max: 100
    property real warnAt: 75
    property real dangerAt: 90
    property color fill: Theme.primary
    implicitHeight: 4
    radius: 2
    color: Theme.outlineVariant
    Rectangle {
      width: track.value >= 0 ? Math.max(2, track.width * Math.min(1, track.value / track.max)) : 0
      implicitHeight: parent.height
      radius: parent.radius
      color: track.value >= track.dangerAt ? Theme.danger
        : track.value >= track.warnAt ? Theme.warning : track.fill
      Behavior on width {
        NumberAnimation { duration: 240; easing.type: Easing.OutQuart }
      }
    }
  }

  // Collapsible section header. `open` is deliberately constant-bound rather
  // than `open: someExpression`: a binding here would be re-evaluated on every
  // state poll and slam the section shut ~1s after the user opened it.
  component Disclosure: Rectangle {
    id: d
    property string title: ""
    property string subtitle: ""
    property color titleColor: Theme.subtext
    property bool open: false
    width: sv.width - 16
    height: 28
    implicitHeight: height
    radius: 8
    color: Theme.surfaceVariant
    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: 9
      anchors.rightMargin: 8
      spacing: 7
      Text {
        text: d.open ? "▾" : "▸"
        color: Theme.muted
        font { family: Fonts.mono; pixelSize: 12 }
      }
      Text {
        text: d.title
        color: d.titleColor
        font { family: Fonts.main; pixelSize: 12; weight: 700; letterSpacing: 1.1 }
      }
      Text {
        text: d.subtitle
        color: Theme.muted
        font { family: Fonts.mono; pixelSize: 11 }
        elide: Text.ElideRight
        Layout.fillWidth: true
      }
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: d.open = !d.open
    }
  }

  readonly property var def: modeSvc ? ModeDefs.def(modeSvc.currentMode) : ModeDefs.def("balanced")
  readonly property bool applying: modeSvc ? modeSvc.transitionState === "applying" : false
  readonly property bool done: modeSvc ? modeSvc.transitionState === "done" : false
  readonly property bool onBattery: modeSvc ? !modeSvc.acPowered : false
  // Heavy modes on battery ask first instead of being blocked outright.
  property string pendingMode: ""

  function deg(v) { return v > 0 ? v.toFixed(0) + "°C" : "—" }
  function pct(v) { return v >= 0 ? v.toFixed(0) + "%" : "—" }
  function cardW() {
    if (sv.width >= 360) return (sv.width - 16) / 3
    return (sv.width - 8) / 2
  }

  readonly property int tileCols: sv.width >= 330 ? 3 : 2
  readonly property int tileRows: Math.ceil(liveTiles.length / tileCols)
  function tileW() { return (sv.width - (tileCols - 1) * 6) / tileCols }

  // Comparable form for requested-vs-effective: "Manual 90%" and "90" are the
  // same intent, "Automatic" and "auto" are the same policy.
  function norm(v) {
    if (v === undefined || v === null)
      return ""
    var s = String(v).toLowerCase().trim()
    if (s === "automatic") return "auto"
    s = s.replace(/^manual /, "")
    s = s.replace(/%$/, "")
    return s
  }

  // An unsupported lever is an *optional* dependency that happens to be
  // missing, not a failed apply — GameMode, EPP on acpi-cpufreq. Only a real
  // failure gets the danger colour, so the red styling stays meaningful.
  function statusColor(s) {
    if (s === "ok") return Theme.success
    if (s === "unsupported") return Theme.muted
    if (s === "failed") return Theme.danger
    return Theme.muted
  }

  function statusLabel(s) {
    if (s === "ok") return "OK"
    if (s === "unsupported") return "OPTIONAL"
    if (s === "failed") return "FAILED"
    return s !== undefined && s !== null && s !== "" ? s : "—"
  }

  function noteColor(n) {
    if (!n) return Theme.subtext
    var l = n.toLowerCase()
    if (l.indexOf("failed") >= 0 || l.indexOf("error") >= 0)
      return Theme.danger
    return Theme.subtext
  }

  function tempColor(c) {
    if (!modeSvc || c <= 0) return Theme.text
    if (c >= modeSvc.thermalHardThreshold) return Theme.danger
    if (c >= modeSvc.thermalThreshold) return Theme.warning
    return Theme.text
  }

  function isOptionalLever(name) {
    return String(name).toLowerCase().indexOf("gamemode") >= 0
  }

  // True when the live readback says no gamemoderun on the box. effective()
  // always re-evaluates it, so this is a presence check and not a memory of
  // the last mode's config.
  readonly property bool gamemodeMissing:
      modeSvc && modeSvc.effectiveGamemode === "not installed"

  // --- live model rows -----------------------------------------------------
  // These JS arrays are model sources for the Repeaters. Declared as bound
  // property vars on the root so every delegate scope can see them, they stay
  // reactive: QML registers every modeSvc.<prop> access made while the binding
  // evaluates, so the arrays re-materialize (and the UI re-renders) whenever
  // the monitor or the controller state changes.

  // One tile per reading, label + value + bar. The long-form extras (clock,
  // VRAM, wattage, free RAM, fan curve) are not per-tile subtitles any more —
  // they would triple the strip's height — they live on one elided line under
  // it, where every number is still present.
  property var liveTiles: [
    {
      label: "CPU", main: modeSvc ? pct(modeSvc.monitor.cpuAvailable ? modeSvc.cpuUsage : -1) : "—",
      value: modeSvc && modeSvc.monitor.cpuAvailable ? modeSvc.cpuUsage : -1,
      max: 100, warnAt: 75, dangerAt: 90
    },
    {
      label: "GPU", main: modeSvc ? pct(modeSvc.gpuAvailable ? modeSvc.gpuUsage : -1) : "—",
      value: modeSvc && modeSvc.gpuAvailable ? modeSvc.gpuUsage : -1,
      max: 100, warnAt: 75, dangerAt: 90
    },
    {
      label: "iGPU", main: modeSvc && modeSvc.monitor.igpuUsage >= 0 ? pct(modeSvc.monitor.igpuUsage) : "—",
      value: modeSvc ? modeSvc.monitor.igpuUsage : -1,
      max: 100, warnAt: 75, dangerAt: 90
    },
    {
      label: "MEM", main: modeSvc && modeSvc.memUsage > 0 ? pct(modeSvc.memUsage) : "—",
      value: modeSvc ? modeSvc.memUsage : -1,
      max: 100, warnAt: 80, dangerAt: 92
    },
    {
      label: "FAN",
      main: modeSvc && modeSvc.fanPct >= 0 ? Math.round(modeSvc.fanPct) + "%"
          : (modeSvc && modeSvc.fanRpm > 0 ? modeSvc.fanRpm + " RPM" : "n/a"),
      value: modeSvc ? modeSvc.fanPct : -1,
      max: 100, warnAt: 85, dangerAt: 95
    },
    {
      label: "PWR", main: modeSvc ? (modeSvc.acPowered ? "AC" : "BAT") : "—",
      sub: modeSvc && modeSvc.monitor.batCap >= 0 ? modeSvc.monitor.batCap + "%" : "",
      value: modeSvc ? modeSvc.monitor.batCap : -1,
      max: 100, warnAt: 25, dangerAt: 12,
      textColor: modeSvc ? (modeSvc.acPowered ? Theme.subtext
          : (modeSvc.monitor.batCap >= 0 && modeSvc.monitor.batCap <= 15 ? Theme.warning : Theme.text))
        : Theme.text
    }
  ]

  property var liveDetail: {
    if (!modeSvc) return ""
    var p = []
    if (modeSvc.cpuFreqMHz > 0) p.push(modeSvc.cpuFreqMHz + " MHz")
    if (modeSvc.gpuAvailable && modeSvc.vramTotalMB > 0)
      p.push("VRAM " + modeSvc.vramUsedMB + "/" + modeSvc.vramTotalMB + " MiB")
    if (modeSvc.gpuAvailable && modeSvc.gpuPowerW > 0)
      p.push(modeSvc.gpuPowerW.toFixed(1) + " W")
    if (modeSvc.monitor.memTotalGiB > 0)
      p.push(modeSvc.monitor.memAvailGiB.toFixed(1) + "/" + modeSvc.monitor.memTotalGiB.toFixed(1) + " GiB free")
    if (modeSvc.effectiveFanCurve) p.push("fan " + modeSvc.effectiveFanCurve)
    return p.join(" · ")
  }

  // Requested vs effective readback. `requested` comes from the controller's
  // config at apply time; `effective` is read back from the hardware right
  // now. A mismatch is either a lever that failed or the thermal guard easing
  // policy — the rows say which, instead of leaving the user to guess.
  //
  // `cmp: false` marks a readback that is a live measurement rather than a
  // setpoint. nbfc reports the fan's instantaneous speed, so comparing it with
  // the configured percentage would flag a mismatch on every single poll and
  // teach the user to ignore the highlight.
  //
  // Rows empty on both sides are dropped: EPP on acpi-cpufreq, and GameMode in
  // every mode that never asked for it, would otherwise pad the table with
  // dashes. A row reappears by itself the moment its value becomes readable.
  readonly property var effRows: _effRows()

  function _effRows() {
    if (!modeSvc) return []
    var out = []
    function push(o) {
      var r = o.cmp === false ? "" : modeSvc.req(o.key || "")
      var e = o.eff || ""
      if (r === "" && e === "")
        return
      out.push({
        label: o.label,
        req: r,
        value: e,
        differs: r !== "" && e !== "" && sv.norm(r) !== sv.norm(e),
        eased: o.eased === true && modeSvc.thermalActive,
        optional: o.optional === true
      })
    }
    push({ label: "Governor", key: "governor", eff: modeSvc.effectiveGovernor, eased: true })
    push({ label: "CPU boost", key: "boost", eff: modeSvc.effectiveBoost, eased: true })
    push({ label: "EPP", eff: modeSvc.effectiveEpp })
    push({ label: "NVIDIA power", key: "nvidia_runtime_pm", eff: modeSvc.effectiveNvPm })
    push({ label: "Persistence", key: "nvidia_persistence", eff: modeSvc.effectivePersistence })
    push({ label: "PPD profile", key: "power_profile", eff: modeSvc.effectivePpd })
    push({ label: "Fan · live", key: "fan_curve", eff: modeSvc.effectiveFanCurve, cmp: false })
    push({ label: "GameMode", key: "gamemode", eff: modeSvc.effectiveGamemode, optional: true })
    push({ label: "swappiness", key: "swappiness", eff: modeSvc.effectiveSwappiness })
    push({ label: "page-cluster", key: "page_cluster", eff: modeSvc.effectivePageCluster })
    push({ label: "vfs cache", key: "vfs_cache_pressure", eff: modeSvc.effectiveVfs })
    return out
  }

  // Resolved sysfs paths, for when the panel's numbers look wrong and the
  // first question is "which file is it reading?".
  readonly property string sensorPaths: _sensorPaths()

  // A collapsed header has ~370px to work with, and the raw sensor list
  // ("k10temp · amdgpu · hp · ac · BAT0 …") does not fit at a legible size.
  // The header carries the count; the wrapped list stays in the body, and a
  // failed discovery is already spelled out by the warning banner above.
  readonly property string diagSubtitle: {
    if (!modeSvc) return "—"
    var m = modeSvc.monitor
    var probe = "probe " + (m.lastProbe || "—") + " · " + (m.active ? "2s" : "8s") + " poll"
    if (!m.sensorsOk) return probe
    var n = m.sensorSummary ? m.sensorSummary.split(" · ").length : 0
    return n + (n === 1 ? " sensor · " : " sensors · ") + probe
  }

  function _sensorPaths() {
    if (!modeSvc) return ""
    var s = modeSvc.monitor.sensors || {}
    var fans = (s["fans"] || []).join(", ")
    var p = [
      "cpu temp : " + (s["cpu_temp"] || "unresolved"),
      "igpu temp: " + (s["igpu_temp"] || "unresolved"),
      "igpu load: " + (s["igpu_busy"] || "unresolved"),
      "fan rpm  : " + (fans || "none in sysfs - nbfc is authoritative"),
      "ac       : " + ((s["mains"] || []).join(", ") || "unresolved"),
      "battery  : " + (s["battery"] || "unresolved")
    ]
    if (modeSvc.monitor.discoverError !== "")
      p.push("discovery: " + modeSvc.monitor.discoverError)
    return p.join("\n")
  }

  // Height of the levers card: header padding + one row per lever + the
  // optional-dependency hint. Used for both implicitHeight and the layout
  // floor, and they must be the *same* expression: the layout reads
  // minimumHeight while computing implicitHeight, so binding one to the other
  // is a dependency loop.
  // Rows of the mode grid, computed so the flow's height is explicit rather
  // than left to the positioner (which reports one row until it knows a width).
  function _modesHeight() {
    var c = sv.width >= 360 ? 3 : 2
    var rows = Math.ceil(ModeDefs.keys.length / c)
    return rows * 108 + (rows - 1) * 6
  }

  function _leversHeight() {
    return 16 + Math.max(1, modeSvc ? modeSvc.leverList.length : 0) * 18
        + (sv.gamemodeMissing ? 16 : 0)
  }

  readonly property bool effRowsLong: effRows.length > 6

  // Disclosure state, exposed so the panel can open or close sections
  // programmatically.
  property alias policyOpen: policyHdr.open
  property alias diagOpen: diagHdr.open
  property alias histOpen: histHdr.open

  // Seed POLICY DETAILS' initial state once the controller state has actually
  // landed. A binding on `effRows` is not enough: the page completes before the
  // first state.json poll, so a binding would see zero rows on every evaluation
  // and force the section open. Seeding from a signal is not enough either —
  // `leverList` settles from `levers`, which arrives a poll before `effective`,
  // so the first signal still sees no rows to count.
  //
  // So: keep listening, and only latch once there is at least one row to judge
  // by. Every poll after that re-arms the signal, and the first one with a
  // populated readback decides. If the readback never populates, the section
  // simply stays at its default of closed.
  property bool policySeeded: false
  property Connections policySeed: Connections {
    target: modeSvc
    function onLeverListChanged() { sv._seedPolicy() }
    function onEffectiveChanged() { sv._seedPolicy() }
    function onRequestedChanged() { sv._seedPolicy() }
  }
  function _seedPolicy() {
    if (sv.policySeeded || !modeSvc) return
    if (sv.effRows.length === 0) return
    sv.policySeeded = true
    policyHdr.open = !sv.effRowsLong
  }

  function _leverSummary() {
    if (!modeSvc) return ""
    var l = modeSvc.levers
    if (!l) return ""
    var ok = 0, opt = 0, fail = 0
    for (var k in l) {
      if (!l.hasOwnProperty(k)) continue
      var st = l[k]["status"]
      if (st === "ok") ok++
      else if (st === "unsupported") opt++
      else if (st === "failed") fail++
    }
    var s = ok + "/" + Object.keys(l).length + " levers applied"
    if (opt) s += " · " + opt + " optional"
    if (fail) s += " · " + fail + " failed"
    return s
  }

  // A Column (positioner), not a ColumnLayout, and every section states an
  // explicit `height`. A ColumnLayout negotiates size against whatever height
  // it is given, and on a page whose content is taller than the panel that
  // negotiation went wrong twice: the levers card was compressed by ~80px until
  // its rows overlapped, and the layout's own implicitHeight under-reported
  // what the ScrollView should scroll, clipping the footer. A positioner only
  // stacks children's heights, so `col.implicitHeight` is exactly the sum and
  // the page just scrolls when it is tall.
  Column {
    id: col
    width: sv.width
    spacing: 6

    // ---- ERROR (only when a switch failed hard) ----
    Rectangle {
      visible: modeSvc && modeSvc.errorText !== ""
      width: parent.width
      radius: 10
      color: Theme.danger
      implicitHeight: 38
      height: 38
      Text {
        anchors.fill: parent
        anchors.margins: 10
        verticalAlignment: Text.AlignVCenter
        text: "󰅙 " + (modeSvc ? modeSvc.errorText : "")
        color: "#1a0000"
        font { family: Fonts.main; pixelSize: 13; weight: 600 }
        elide: Text.ElideRight
      }
    }

    // ---- BATTERY SOFT-CONFIRM (heavy modes only) ----
    // One line, not a banner: the choice is "switch anyway / dismiss", and
    // the warning is a courtesy rather than a lock.
    Rectangle {
      visible: sv.pendingMode !== ""
      width: parent.width
      radius: 10
      color: Qt.rgba(0.75, 0.90, 0.60, 0.10)
      border.color: Theme.warning
      border.width: 1
      implicitHeight: 32
      height: 32
      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 6
        spacing: 8
        Text {
          text: "⚠"
          color: Theme.warning
          font { family: Fonts.main; pixelSize: 13 }
        }
        Text {
          text: "On battery — " + (sv.pendingMode || "").toUpperCase() + " raises heat"
          color: Theme.subtext
          font { family: Fonts.main; pixelSize: 12; weight: 500 }
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
        Rectangle {
          color: Theme.primary
          radius: 5
          height: 25
          implicitWidth: confirmText.implicitWidth + 14
          Text {
            id: confirmText
            anchors.centerIn: parent
            text: "Switch"
            color: Theme.primaryFg
            font { family: Fonts.main; pixelSize: 12; weight: 700 }
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              var m = sv.pendingMode
              sv.pendingMode = ""
              sv.setMode(m)
            }
          }
        }
        Text {
          text: "✕"
          color: Theme.muted
          font { family: Fonts.mono; pixelSize: 13 }
          MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: sv.pendingMode = ""
          }
        }
      }
    }

    // ---- ACTIVE MODE ----
    // Identity on the left, the one reading that decides whether the selected
    // mode is currently safe on the right (CPU temperature + its guard
    // threshold). The other numbers are in the live strip below.
    Rectangle {
      width: parent.width
      radius: 14
      color: Theme.surfaceVariant
      border.color: done ? Theme.primary : applying ? Theme.warning : "transparent"
      border.width: 1
      implicitHeight: 74
      height: 74

      RowLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 4

          RowLayout {
            Layout.fillWidth: true
            spacing: 7
            Text {
              text: def.icon
              color: Theme.primary
              font { family: Fonts.mono; pixelSize: 20 }
            }
            Text {
              text: sv.applying ? "APPLYING" : def.name
              color: Theme.text
              font { family: Fonts.main; pixelSize: 17; weight: 700 }
            }
            Rectangle {
              visible: sv.applying || sv.done
              color: sv.applying ? Theme.warning : Theme.primary
              radius: 4
              height: 19
              implicitWidth: stateTxt.implicitWidth + 12
              Text {
                id: stateTxt
                anchors.centerIn: parent
                text: sv.applying ? "APPLYING" : "ACTIVE"
                color: sv.applying ? "#1a0000" : Theme.primaryFg
                font { family: Fonts.mono; pixelSize: 11; weight: 700 }
              }
            }
            Item { Layout.fillWidth: true }
            Text {
              text: sv._leverSummary()
              color: Theme.subtext
              font { family: Fonts.mono; pixelSize: 11 }
              elide: Text.ElideRight
              Layout.preferredWidth: 150
              horizontalAlignment: Text.AlignRight
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: 5
            Repeater {
              model: def.chips
              delegate: Rectangle {
                required property string modelData
                color: Theme.surfaceBright
                radius: 4
                height: 19
                implicitWidth: pillTxt.implicitWidth + 9
                Text {
                  id: pillTxt
                  anchors.centerIn: parent
                  text: modelData
                  color: Theme.subtext
                  // 10px, not 11: this row shares its width with the mode
                  // name, the ACTIVE capsule and the lever summary, and at 11px
                  // the gaming chips ("NVIDIA" + "GameMode if installed")
                  // overrun the header and spill over the name.
                  font { family: Fonts.main; pixelSize: 10; weight: 600 }
                }
              }
            }
            Item { Layout.fillWidth: true }
            Text {
              text: def.tag
              color: Theme.muted
              font { family: Fonts.main; pixelSize: 11; weight: 500 }
            }
          }
        }

        // CPU temperature: the reading that gates the active mode.
        ColumnLayout {
          spacing: 3
          Layout.preferredWidth: 96

          Text {
            text: "CPU"
            color: Theme.muted
            font { family: Fonts.main; pixelSize: 11; weight: 700; letterSpacing: 1 }
          }
          Text {
            text: modeSvc && modeSvc.monitor.cpuAvailable
                ? sv.deg(modeSvc.cpuTemp) : "Unavailable"
            color: sv.tempColor(modeSvc ? modeSvc.cpuTemp : 0)
            font { family: Fonts.mono; pixelSize: 18; weight: 600 }
          }
          Meter {
            Layout.fillWidth: true
            implicitHeight: 4
            value: modeSvc && modeSvc.monitor.cpuAvailable ? modeSvc.cpuTemp : -1
            max: 110
            warnAt: modeSvc ? modeSvc.thermalThreshold : 88
            dangerAt: modeSvc ? modeSvc.thermalHardThreshold : 92
          }
        }
      }
    }

    // ---- THERMAL BANNER (only while the guard is easing policy) ----
    Rectangle {
      visible: modeSvc && modeSvc.thermalActive
      width: parent.width
      radius: 10
      color: Qt.rgba(0.75, 0.90, 0.60, 0.10)
      border.color: Theme.warning
      border.width: 1
      implicitHeight: 42
      height: 42
      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 8
        Text {
          text: "⚠"
          color: Theme.warning
          font { family: Fonts.main; pixelSize: 14 }
        }
        Text {
          text: "THERMAL PROTECTION"
            + (modeSvc ? " · " + sv.deg(modeSvc.cpuTemp) + " ≥ " + modeSvc.thermalThreshold
              + "°C · policy eased, resumes below " + modeSvc.thermalResume + "°C"
              + (modeSvc.thermalNote ? " · " + modeSvc.thermalNote : "") : "")
          color: Theme.subtext
          font { family: Fonts.main; pixelSize: 12; weight: 500 }
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }
    }

    // ---- SENSOR DISCOVERY FAILURE ----
    Rectangle {
      visible: modeSvc && !modeSvc.monitor.sensorsOk
      width: sv.width - 16
      x: 8
      radius: 8
      color: "transparent"
      border.color: Theme.warning
      border.width: 1
      implicitHeight: 32
      height: 32
      Text {
        anchors.fill: parent
        anchors.margins: 8
        verticalAlignment: Text.AlignVCenter
        text: "󰅚 Sensors unresolved — " + (modeSvc ? modeSvc.monitor.sensorSummary : "")
        color: Theme.warning
        font { family: Fonts.main; pixelSize: 12; weight: 600 }
        elide: Text.ElideRight
      }
    }

    // ---- MODES (the primary action) ----
    // The Flow itself cannot report a useful implicitHeight (read-only, and it
    // resolves to one row until it knows its width), so it lives in a
    // Rectangle that states the wrapped height for it.
    Rectangle {
      color: "transparent"
      width: sv.width
      height: sv._modesHeight()
      implicitHeight: height

      Flow {
        anchors.fill: parent
        spacing: 6

      Repeater {
        model: ModeDefs.keys
        delegate: Rectangle {
          required property string modelData
          property var d: ModeDefs.def(modelData)
          property bool active: modeSvc && modeSvc.currentMode === modelData
          property bool heavy: modelData === "gaming" || modelData === "ai"
          width: sv.cardW()
          height: 108
          radius: 12
          color: active ? Theme.surfaceBright : Theme.surfaceVariant
          border.color: active ? Theme.primary : "transparent"
          border.width: 1

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              // Heavy modes on battery ask first; everything else applies
              // straight away (the confirm is a courtesy, not a lock).
              if (sv.onBattery && (modelData === "gaming" || modelData === "ai")) {
                sv.pendingMode = modelData
                return
              }
              sv.setMode(modelData)
            }
          }

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4

            RowLayout {
              Layout.fillWidth: true
              spacing: 6
              Text {
                text: d.icon
                color: active ? Theme.primary : Theme.muted
                font { family: Fonts.mono; pixelSize: 17 }
              }
              Text {
                text: d.name
                color: Theme.text
                font { family: Fonts.main; pixelSize: 14; weight: 700 }
                Layout.fillWidth: true
              }
              Text {
                visible: sv.onBattery && heavy && !active
                text: "⚠"
                color: Theme.warning
                font { family: Fonts.main; pixelSize: 12 }
              }
              Text {
                visible: active
                text: "●"
                color: Theme.primary
                font { family: Fonts.main; pixelSize: 11 }
              }
            }

            Text {
              text: d.tag
              color: Theme.muted
              font { family: Fonts.main; pixelSize: 11; weight: 500 }
              Layout.fillWidth: true
              elide: Text.ElideRight
            }

            // Chips wrap instead of ellipsising. A card is ~175px wide, and at a
            // readable size the gaming pair ("NVIDIA" + "GameMode if installed")
            // needs ~168px — squeezing them onto one line meant either
            // truncating the labels or letting them paint over the next card.
            // Two lines costs card height, not legibility.
            Flow {
              id: cardChipRow
              Layout.fillWidth: true
              Layout.preferredHeight: 42
              spacing: 4
              clip: true
              Repeater {
                model: d.chips
                delegate: Rectangle {
                  required property string modelData
                  id: cardPillBox
                  color: Theme.surfaceBright
                  radius: 4
                  height: 19
                  // Capped, not implicitWidth: a Flow hands each child its
                  // implicit width unbounded, so a long label would push the
                  // capsule past the card's inner edge.
                  width: Math.min(cardPill.implicitWidth + 9, cardChipRow.width)
                  Text {
                    id: cardPill
                    anchors.centerIn: parent
                    text: modelData
                    color: Theme.subtext
                    font { family: Fonts.main; pixelSize: 10; weight: 600 }
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, cardPillBox.width - 8)
                  }
                }
              }
            }
          }
        }
      }
      }
    }

    // ---- AUTO MODE ----
    Rectangle {
      width: sv.width - 16
      x: 8
      radius: 8
      color: Theme.surfaceVariant
      implicitHeight: 30
      height: 30
      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 8
        spacing: 8
        Text {
          text: "AUTO"
          color: modeSvc && modeSvc.autoMode ? Theme.primary : Theme.subtext
          font { family: Fonts.main; pixelSize: 12; weight: 700; letterSpacing: 1.1 }
        }
        Text {
          text: "Balanced on AC · Silent on battery (at plug/unplug only)"
          color: Theme.muted
          font { family: Fonts.main; pixelSize: 11 }
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
        Rectangle {
          width: 36
          height: 20
          radius: 10
          color: modeSvc && modeSvc.autoMode ? Theme.primary : Theme.surfaceBright
          border.color: Theme.outline
          border.width: modeSvc && modeSvc.autoMode ? 0 : 1
          Rectangle {
            width: 14
            height: 14
            radius: 7
            y: 3
            x: modeSvc && modeSvc.autoMode ? 19 : 3
            color: modeSvc && modeSvc.autoMode ? Theme.primaryFg : Theme.subtext
            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutQuart } }
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (modeSvc) modeSvc.autoMode = !modeSvc.autoMode
          }
        }
      }
    }

    // ---- LIVE SYSTEM ----
    Rectangle {
      color: "transparent"
      width: sv.width
      height: sv.tileRows * 60 + (sv.tileRows - 1) * 6
      implicitHeight: height

      Grid {
        anchors.fill: parent
        columns: sv.tileCols
        columnSpacing: 6
        rowSpacing: 6

      Repeater {
        model: sv.liveTiles
        delegate: Rectangle {
          required property var modelData
          width: sv.tileW()
          height: 60
          radius: 10
          color: Theme.surfaceVariant

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: 9
            spacing: 2
            Text {
              text: modelData.label
              color: Theme.muted
              font { family: Fonts.main; pixelSize: 11; weight: 700; letterSpacing: 1.1 }
            }
            Text {
              text: modelData.main
                  + (modelData.sub !== undefined && modelData.sub !== "" ? " " + modelData.sub : "")
              color: modelData.textColor !== undefined ? modelData.textColor : Theme.text
              font { family: Fonts.mono; pixelSize: 15; weight: 600 }
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
            Meter {
              Layout.fillWidth: true
              // Every tile supplies these keys; the fallbacks keep a future
              // row from turning a missing scale into a binding error.
              implicitHeight: 3
              value: modelData.value !== undefined ? modelData.value : -1
              max: modelData.max !== undefined ? modelData.max : 100
              warnAt: modelData.warnAt !== undefined ? modelData.warnAt : 85
              dangerAt: modelData.dangerAt !== undefined ? modelData.dangerAt : 95
            }
          }
        }
      }
      }
    }

    // ---- CPU TEMP TREND (last 24 probes) ----
    RowLayout {
      width: sv.width - 16
      x: 8
      spacing: 8
      visible: modeSvc && modeSvc.monitor.tempSamples.length > 1
      Text {
        text: "TEMP"
        color: Theme.muted
        font { family: Fonts.main; pixelSize: 11; weight: 700; letterSpacing: 1.1 }
      }
      // Fixed 24 slots bound to the ring buffer: only bindings update as
      // samples arrive, so the shape never rebuilds itself mid-scroll.
      Row {
        id: spark
        Layout.fillWidth: true
        height: 20
        spacing: 1
        Repeater {
          model: 24
          delegate: Rectangle {
            required property int index
            width: (spark.width - 23) / 24
            height: spark.height
            color: "transparent"
            readonly property real s: modeSvc && index < modeSvc.monitor.tempSamples.length
              ? modeSvc.monitor.tempSamples[index] : -1
            Rectangle {
              anchors.bottom: parent.bottom
              width: parent.width
              // 30..100°C window, so ordinary idle variation is visible
              height: s >= 0 ? Math.max(2, parent.height * Math.min(1, Math.max(0, (s - 30) / 70))) : 0
              radius: 1
              color: s >= 100 ? Theme.danger : s >= 88 ? Theme.warning : Theme.primary
              opacity: s >= 0 ? 0.9 : 0
              Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutQuart } }
            }
          }
        }
      }
    }

    // ---- every remaining reading, on one elided line ----
    Text {
      width: sv.width - 16
      x: 8
      visible: sv.liveDetail !== ""
      text: sv.liveDetail
      color: Theme.muted
      font { family: Fonts.mono; pixelSize: 11 }
      elide: Text.ElideRight
    }

  // ---- LEVERS ----
    Rectangle {
      width: sv.width - 16
      x: 8
      radius: 10
      color: Theme.surfaceVariant
      // Levers come and go as the backend reports them, so the card is sized
      // from the list rather than trusted to a layout.
      height: sv._leversHeight()
      implicitHeight: height

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 1

        Repeater {
          model: modeSvc ? modeSvc.leverList : []
          delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 6
            Text {
              text: modelData.name
              color: Theme.subtext
              font { family: Fonts.main; pixelSize: 12; weight: 600 }
              Layout.preferredWidth: 68
              elide: Text.ElideRight
            }
            Rectangle {
              width: leverStatusTxt.implicitWidth + 11
              height: 17
              radius: 3
              color: "transparent"
              border.color: sv.statusColor(modelData.status)
              border.width: 1
              Text {
                id: leverStatusTxt
                anchors.centerIn: parent
                text: sv.statusLabel(modelData.status)
                color: sv.statusColor(modelData.status)
                font { family: Fonts.mono; pixelSize: 11; weight: 700 }
              }
            }
            Text {
              text: modelData.note === "" ? "" : modelData.note
              color: sv.noteColor(modelData.note)
              font { family: Fonts.main; pixelSize: 12 }
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }
        }

        Text {
          visible: !modeSvc || modeSvc.leverList.length === 0
          text: "no lever results yet — switch a mode once"
          color: Theme.muted
          font { family: Fonts.main; pixelSize: 12 }
        }

        // Quiet, non-blocking hint for the one optional lever that is missing.
        // Sits next to the OPTIONAL chip that explains why it is missing, and
        // never gates the mode: gaming works without it.
        Text {
          visible: sv.gamemodeMissing
          text: "Optional · install gamemode for extra gaming tweaks (pacman -S gamemode lib32-gamemode)"
          color: Theme.muted
          font { family: Fonts.main; pixelSize: 11 }
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }
    }

    // ---- POLICY DETAILS (collapsed when the table is long) ----
    Disclosure {
      id: policyHdr
      x: 8
      title: "POLICY DETAILS"
      subtitle: sv.effRows.length + " readback rows · " + (sv.def.name)
    }

    ColumnLayout {
      visible: policyHdr.open
      width: parent.width
      spacing: 6

      // where the active mode sits on the efficiency→performance axis
      Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        // Tall enough for the marker dot and the "▲ MODE" label anchored below
        // it: 36 = dot top 13 + 6 + 2 margin + 15px label line.
        implicitHeight: 36
        color: "transparent"

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: 4
          radius: 2
          color: Theme.outlineVariant
        }

        Repeater {
          model: ModeDefs.data
          delegate: Rectangle {
            required property var modelData
            property real progX: modelData.profile / 100 * parent.parent.width
            width: 1
            height: 4
            color: Theme.outline
            x: progX
            y: parent.verticalCenter - 2
          }
        }

        Rectangle {
          property real px: (sv.def.profile / 100) * parent.width
          x: px - 3
          y: parent.height / 2 - 5
          width: 6
          height: 6
          radius: 3
          color: Theme.primary
          Text {
            anchors.top: parent.bottom
            anchors.topMargin: 2
            anchors.horizontalCenter: parent.horizontalCenter
            text: "▲ " + sv.def.name
            color: Theme.primary
            font { family: Fonts.main; pixelSize: 10; weight: 700 }
          }
        }
      }

      // what the mode intends, in words
      Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        radius: 10
        color: Theme.surfaceVariant
        implicitHeight: 32 + sv.def.config.length * 16
        ColumnLayout {
          anchors.fill: parent
          anchors.margins: 8
          spacing: 1
          Text {
            text: sv.def.name.toUpperCase() + " — intent"
            color: Theme.muted
            font { family: Fonts.main; pixelSize: 11; weight: 700; letterSpacing: 1.1 }
          }
          Repeater {
            model: sv.def.config
            delegate: RowLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: 8
              Text {
                text: modelData[0]
                color: Theme.subtext
                font { family: Fonts.main; pixelSize: 11 }
                Layout.fillWidth: true
                elide: Text.ElideRight
              }
              Text {
                text: modelData[1]
                color: Theme.text
                font { family: Fonts.main; pixelSize: 11; weight: 600 }
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                Layout.preferredWidth: 170
              }
            }
          }
        }
      }

      // what was asked for vs what the hardware is actually doing
      Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        radius: 10
        color: Theme.surfaceVariant
        implicitHeight: 32 + sv.effRows.length * 16
        ColumnLayout {
          anchors.fill: parent
          anchors.margins: 8
          spacing: 1
          Text {
            text: modeSvc && modeSvc.req("governor") === ""
              ? "read back from hardware — no requested baseline yet"
              : "requested (left) → effective (right)"
            color: Theme.muted
            font { family: Fonts.main; pixelSize: 11; weight: 700; letterSpacing: 1.1 }
            Layout.fillWidth: true
            elide: Text.ElideRight
          }
          Repeater {
            model: sv.effRows
            delegate: RowLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: 4
              Text {
                text: modelData.label
                color: Theme.subtext
                font { family: Fonts.main; pixelSize: 11 }
                Layout.preferredWidth: 84
                elide: Text.ElideRight
              }
              Text {
                visible: modelData.req !== ""
                text: modelData.req
                color: Theme.muted
                font { family: Fonts.mono; pixelSize: 11 }
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                Layout.preferredWidth: 100
              }
              Text {
                visible: modelData.req !== ""
                text: "→"
                color: Theme.muted
                font { family: Fonts.mono; pixelSize: 11 }
              }
              Text {
                text: modelData.value === "" ? "—" : modelData.value
                color: modelData.optional ? Theme.subtext
                  : (modelData.differs || modelData.eased ? Theme.warning : Theme.text)
                font { family: Fonts.mono; pixelSize: 11; weight: 600 }
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                Layout.preferredWidth: 130
              }
              Text {
                visible: modelData.eased
                text: "eased"
                color: Theme.warning
                font { family: Fonts.main; pixelSize: 10; weight: 700 }
              }
              Item { Layout.fillWidth: true }
            }
          }
        }
      }
    }

    // ---- DIAGNOSTICS (default collapsed) ----
    Disclosure {
      id: diagHdr
      x: 8
      title: "DIAGNOSTICS"
      titleColor: modeSvc && !modeSvc.monitor.sensorsOk ? Theme.warning : Theme.subtext
      subtitle: sv.diagSubtitle
    }

    ColumnLayout {
      visible: diagHdr.open
      width: parent.width
      spacing: 6

      Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        radius: 8
        color: "transparent"
        border.color: Theme.outlineVariant
        border.width: 1
        implicitHeight: pathBody.implicitHeight + 16
        Text {
          id: pathBody
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 8
          text: sv.sensorPaths
          color: Theme.muted
          font { family: Fonts.mono; pixelSize: 11 }
          wrapMode: Text.Wrap
        }
      }

      Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        radius: 8
        color: Theme.primary
        implicitHeight: 30
        Text {
          anchors.centerIn: parent
          text: modeSvc && modeSvc.doctorRunning ? "running…" : "RUN DOCTOR"
          color: modeSvc && modeSvc.doctorRunning ? Theme.subtext : Theme.primaryFg
          font { family: Fonts.main; pixelSize: 12; weight: 700 }
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: if (modeSvc) modeSvc.runDoctor()
        }
      }

      Rectangle {
        visible: modeSvc && modeSvc.doctorText !== ""
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        radius: 8
        color: Theme.background
        border.color: Theme.outlineVariant
        border.width: 1
        implicitHeight: doctorBody.implicitHeight + 16
        Text {
          id: doctorBody
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 8
          text: modeSvc ? modeSvc.doctorText : ""
          color: Theme.subtext
          font { family: Fonts.mono; pixelSize: 11 }
          wrapMode: Text.Wrap
        }
      }
    }

    // ---- SWITCH HISTORY (default collapsed) ----
    Disclosure {
      id: histHdr
      x: 8
      title: "SWITCH HISTORY"
      subtitle: modeSvc && modeSvc.switchHistory.length > 0
        ? modeSvc.switchHistory.length + " this session"
        : "none yet"
    }

    Rectangle {
      visible: histHdr.open
      width: sv.width - 16
      x: 8
      radius: 10
      color: Theme.surfaceVariant
      implicitHeight: 16 + Math.max(1, modeSvc ? modeSvc.switchHistory.length : 0) * 17
      height: 16 + Math.max(1, modeSvc ? modeSvc.switchHistory.length : 0) * 17
      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 1
        Repeater {
          model: modeSvc ? modeSvc.switchHistory : []
          delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 8
            Text {
              text: modeSvc ? modeSvc.timeString(modelData.t) : ""
              color: Theme.muted
              font { family: Fonts.mono; pixelSize: 11 }
            }
            Text {
              text: modelData.mode
              color: modelData.ok ? Theme.text : Theme.danger
              font { family: Fonts.main; pixelSize: 12; weight: 600 }
            }
            Text {
              text: modelData.auto ? "auto" : "manual"
              color: Theme.muted
              font { family: Fonts.main; pixelSize: 11 }
            }
            Item { Layout.fillWidth: true }
          }
        }
        Text {
          visible: !modeSvc || modeSvc.switchHistory.length === 0
          text: "no switches yet"
          color: Theme.muted
          font { family: Fonts.main; pixelSize: 12 }
        }
      }
    }

    // ---- FOOTER ----
    RowLayout {
      width: sv.width - 16
      x: 8
      spacing: 8
      Text {
        text: modeSvc ? modeSvc.currentMode.toUpperCase() + " · changed " + modeSvc.lastChangeString
          : "—"
        color: Theme.muted
        font { family: Fonts.main; pixelSize: 11; weight: 600; letterSpacing: 1 }
      }
      Item { Layout.fillWidth: true }
      Text {
        text: modeSvc && modeSvc.thermalActive
          ? "PROTECTION ACTIVE (" + modeSvc.thermalStage.toUpperCase() + ")"
          : "PROTECTION IDLE · resume " + (modeSvc ? modeSvc.thermalResume : 82) + "°C"
        color: modeSvc && modeSvc.thermalActive ? Theme.warning : Theme.muted
        font { family: Fonts.main; pixelSize: 11; weight: 600; letterSpacing: 1 }
      }
    }
  }
}
