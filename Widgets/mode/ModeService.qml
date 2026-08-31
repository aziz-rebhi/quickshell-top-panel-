import Quickshell
import Quickshell.Io
import QtQuick
import "../../core"

/*
 * Thin client for the performance-mode controller (performance-mode/bin/).
 * The controller owns all policy; this service displays what was applied,
 * what is actually effective on the hardware, and any active thermal guard,
 * and forwards UI requests to the CLI.
 *
 * Selected vs. effective: `currentMode` is what the user chose. The state
 * file's `effective` / `thermal` / `levers` blocks describe what the system
 * is really doing right now, which can differ (thermal mitigation eases the
 * policy, a lever may be unsupported, the guard never touches `mode`).
 *
 * State is polled by reading the file directly on a timer. FileView is not
 * used: the controller writes state.json atomically (temp file + rename), so
 * a file watcher bound to the old inode never fires, which froze the service
 * on a stale mode forever.
 */

QtObject {
  id: _root

  readonly property var modes: ["silent", "balanced", "performance", "gaming", "ai"]
  property string currentMode: "balanced"
  property string errorText: ""

  // Live hardware monitor (drives cpuTemp and the Live System section)
  property MonitorService monitor: MonitorService {}

  readonly property real cpuTemp: monitor.cpuTemp
  readonly property int cpuUsage: monitor.cpuUsage
  readonly property int cpuFreqMHz: monitor.cpuFreqMHz
  readonly property int gpuTemp: monitor.gpuTemp
  readonly property int gpuUsage: monitor.gpuUsage
  readonly property bool gpuAvailable: monitor.gpuAvailable
  readonly property int vramUsedMB: monitor.vramUsedMB
  readonly property int vramTotalMB: monitor.vramTotalMB
  readonly property real gpuPowerW: monitor.gpuPowerW
  readonly property int fanRpm: monitor.fanRpm
  readonly property int fanPct: monitor.fanPct

  // Per-lever application results from the last switch
  property var levers: ({})
  // Real, current hardware policy read back by the controller
  property var effective: ({})

  // Flattened effective-policy readbacks (bound to the state var above)
  readonly property string effectiveGovernor: effective["governor"] || ""
  readonly property string effectiveBoost: effective["boost"] || ""
  readonly property string effectiveEpp: effective["epp"] || ""
  readonly property string effectiveNvPm: effective["nvidia_runtime_pm"] || ""
  readonly property string effectivePersistence: effective["nvidia_persistence"] || ""
  readonly property string effectivePpd: effective["power_profile"] || ""
  readonly property string effectiveGamemode: effective["gamemode"] || ""
  readonly property string effectiveFanCurve: effective["fan_curve"] || ""
  readonly property string effectiveSwappiness: effective["swappiness"] || ""
  readonly property string effectivePageCluster: effective["page_cluster"] || ""
  readonly property string effectiveVfs: effective["vfs_cache_pressure"] || ""

  // Thermal guard state (progressive protection, live from the watcher)
  property bool thermalActive: false
  property string thermalStage: ""
  property int thermalThreshold: 88
  property int thermalHardThreshold: 92
  property int thermalResume: 82
  property string thermalNote: ""
  property real thermalLastTemp: 0
  property real thermalSince: 0

  // Switch transition state: "idle" -> "applying" -> "done"
  property string transitionState: "idle"
  property string transitionMode: ""

  property real lastChange: 0

  readonly property string statePath: "/var/lib/performance-mode/state.json"
  readonly property string binPath: Quickshell.shellPath("performance-mode/bin/performance-mode")

  property bool _applying: false

  property Timer pollTimer: Timer {
    interval: 4000
    repeat: true
    running: true
    onTriggered: _root._readState()
  }

  property Process _stateProc: Process {
    stdout: StdioCollector {
      onStreamFinished: _root._parseState(this.text)
    }
  }

  // Clears the "done" flash after a successful switch
  property Timer doneTimer: Timer {
    interval: 1800
    repeat: false
    onTriggered: {
      _root.transitionState = "idle"
      _root.transitionMode = ""
    }
  }

  function _readState() {
    _stateProc.command = ["cat", statePath];
    _stateProc.running = true;
  }

  function _parseState(raw) {
    raw = String(raw || "").trim();
    if (!raw) return;
    try {
      var s = JSON.parse(raw);
      var hasLevers = s.levers !== undefined && s.levers !== null;
      if (s.mode && modes.indexOf(s.mode) !== -1) {
        currentMode = s.mode;
        if (s.time) lastChange = s.time;
        if (!_applying) errorText = "";
      }
      if (hasLevers) {
        levers = s.levers;
        effective = s.effective !== undefined && s.effective !== null ? s.effective : ({});
        var t = s.thermal !== undefined && s.thermal !== null ? s.thermal : ({});
        thermalActive = t["active"] === true;
        thermalStage = t["stage"] || "";
        if (t["threshold"]) thermalThreshold = t["threshold"];
        if (t["hard_threshold"]) thermalHardThreshold = t["hard_threshold"];
        if (t["resume"]) thermalResume = t["resume"];
        thermalLastTemp = t["last_temp"] || 0;
        thermalSince = t["since"] || 0;
        thermalNote = t["note"] || "";
        if (transitionState === "applying" && s.mode === transitionMode) {
          transitionState = "done";
          doneTimer.restart();
        }
      }
    } catch (e) {
      console.warn("ModeService: invalid state file");
    }
  }

  function leverStatus(key) {
    var l = levers[key];
    return l ? l["status"] : "";
  }

  function leverNote(key) {
    var l = levers[key];
    return l && l["note"] ? l["note"] : "";
  }

  function setMode(mode) {
    if (modes.indexOf(mode) === -1 || mode === currentMode) return;
    if (_applying) return;
    _applying = true;
    errorText = "";
    transitionMode = mode;
    transitionState = "applying";
    var proc = Qt.createQmlObject(
      'import QtQuick; import Quickshell.Io;' +
      'Process { command: ["' + binPath + '", "set", "' + mode + '"]; stderr: StdioCollector {} }',
      _root);
    proc.exited.connect(function(code) {
      _applying = false;
      if (code === 0) {
        _readState();
      } else {
        transitionState = "idle";
        transitionMode = "";
        var err = proc.stderr && proc.stderr.text ? proc.stderr.text.trim().split("\n").pop() : "";
        errorText = "Mode switch failed (exit " + code + ")" + (err ? ": " + err : "")
            + ". Run `sudo ./performance-mode/install.sh` once.";
        console.warn("ModeService: " + errorText);
      }
      proc.destroy();
    });
    proc.running = true;
  }

  function cycleMode() {
    var idx = modes.indexOf(currentMode);
    var nxt = idx === -1 || idx >= modes.length - 1 ? modes[0] : modes[idx + 1];
    setMode(nxt);
  }

  function timeString(ts) {
    if (!ts) return "—";
    return new Date(ts * 1000).toLocaleTimeString(Qt.locale(), "HH:mm:ss");
  }

  readonly property string lastChangeString: timeString(lastChange)
  readonly property string thermalSinceString: thermalSince > 0 ? timeString(thermalSince) : "—"

  Component.onCompleted: {
    _readState();
  }
}