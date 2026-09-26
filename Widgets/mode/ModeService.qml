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
 * file's `requested` / `effective` / `thermal` / `levers` blocks describe
 * what the system is really doing right now, which can differ (thermal
 * mitigation eases the policy, a lever may be unsupported, the guard never
 * touches `mode` or `requested`).
 *
 * State is polled by reading the file directly on a timer. FileView is not
 * used: the controller writes state.json atomically (temp file + rename), so
 * a file watcher bound to the old inode never fires, which froze the service
 * on a stale mode forever. The poll is fast while the page is open or a
 * switch is in flight, lazy otherwise — a 1.2s `cat` forever is pointless
 * when nothing is watching.
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
  readonly property real fanPct: monitor.fanPct
  readonly property int igpuTemp: monitor.igpuTemp
  readonly property bool igpuAvailable: monitor.igpuAvailable
  readonly property int memUsage: monitor.memUsage
  readonly property bool acPowered: monitor.acPowered

  // True while the Performance page is on screen. Drives both poll rates:
  // the state file and the hardware probe.
  property bool pageActive: false

  // Probe at full rate while the page is open or a switch is in flight.
  // (QtObject has no default property, so helper objects are named props.)
  property Binding monitorActive: Binding {
    target: _root.monitor
    property: "active"
    value: _root.pageActive || _root.transitionState === "applying"
    restoreMode: Binding.RestoreBindingOrValue
  }

  // Per-lever application results from the last switch
  property var levers: ({})
  // What the mode asked for (from the controller's config, recorded at apply)
  property var requested: ({})
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

  // Lever rows for the page's per-lever list, in the controller's own order.
  readonly property var leverList: {
    var out = []
    var l = _root.levers
    for (var k in l) {
      if (l.hasOwnProperty(k))
        out.push({ name: k, status: l[k]["status"] || "", note: l[k]["note"] || "" })
    }
    return out
  }

  // Requested value for a lever key, or "" when the controller predates the
  // `requested` block (the page then shows effective values only).
  function req(key) {
    if (!_root.requested || _root.requested[key] === undefined || _root.requested[key] === null)
      return ""
    return String(_root.requested[key])
  }

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

  // Recent switches, newest first (in memory — no file for something the
  // session already knows; a persistent log is a bigger question than this
  // page needs to answer).
  property var switchHistory: []

  // Auto mode: prefer balanced on AC, silent on battery. Off by default and
  // only ever acted on at a power-source transition, so it never fights the
  // user mid-session.
  property bool autoMode: false

  property bool _applying: false
  property real lastManualSwitch: 0
  // Set while the preference is being read back, so loading it does not
  // immediately write the file it came from.
  property bool _readingAuto: false

  property Timer pollTimer: Timer {
    // Fast while the page is open or a switch is applying, lazy otherwise.
    interval: _root.pageActive || _root.transitionState === "applying" ? 1200 : 6000
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

  // A switch that never lands must not strand the page on APPLYING. After
  // this long we report what we know, go back to idle and re-read — the
  // switch may still land afterwards, and the controller writes state.json
  // before it exits, so a late poll corrects the UI either way.
  property Timer applyTimer: Timer {
    interval: 15000
    repeat: false
    onTriggered: _root._onApplyTimeout()
  }

  readonly property string statePath: "/var/lib/performance-mode/state.json"
  readonly property string binPath: Quickshell.shellPath("performance-mode/bin/performance-mode")

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
      if (s.requested !== undefined && s.requested !== null)
        requested = s.requested;
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
          applyTimer.stop();
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

  // Heavy modes on battery: the page soft-confirms instead of blocking, so
  // the user keeps one-click access when they know what they want.
  function requiresAcConfirm(mode) {
    return (mode === "gaming" || mode === "ai") && !monitor.acPowered;
  }

  function _pushHistory(mode, ok, auto) {
    var a = switchHistory.slice();
    a.unshift({ t: Math.floor(Date.now() / 1000), mode: mode, ok: ok === true, auto: auto === true });
    if (a.length > 5)
      a = a.slice(0, 5);
    switchHistory = a;
  }

  function setMode(mode, auto) {
    if (modes.indexOf(mode) === -1) return;
    if (_applying) return;
    if (mode === currentMode) {
      // Already there: no CLI call, no APPLYING flash — just confirm the
      // state file agrees and show ACTIVE.
      _readState();
      transitionMode = mode;
      transitionState = "done";
      doneTimer.restart();
      return;
    }
    _applying = true;
    errorText = "";
    transitionMode = mode;
    transitionState = "applying";
    applyTimer.restart();
    if (!auto)
      lastManualSwitch = Date.now() / 1000;
    var proc = Qt.createQmlObject(
      'import QtQuick; import Quickshell.Io;' +
      'Process { command: ["' + binPath + '", "set", "' + mode + '"]; stderr: StdioCollector {} }',
      _root);
    proc.exited.connect(function(code) {
      applyTimer.stop();
      _applying = false;
      if (code === 0) {
        // The controller writes state.json before exiting; the poll picks the
        // new mode up within one interval and flips APPLYING to ACTIVE.
        _readState();
        _pushHistory(mode, true, auto);
      } else {
        transitionState = "idle";
        transitionMode = "";
        var err = proc.stderr && proc.stderr.text ? proc.stderr.text.trim().split("\n").pop() : "";
        errorText = "Mode switch failed (exit " + code + ")" + (err ? ": " + err : "")
            + ". Run `sudo ./performance-mode/install.sh` once.";
        console.warn("ModeService: " + errorText);
        _pushHistory(mode, false, auto);
      }
      proc.destroy();
    });
    proc.running = true;
  }

  function _onApplyTimeout() {
    if (transitionState !== "applying") return;
    var mode = transitionMode;
    // Release the switch lock so the page stays usable: a wedged sudo call
    // should not disable the mode buttons too. The orphaned process is left
    // alone (killing it mid-apply would leave a half-applied policy) and its
    // exit handler still re-reads state if it ever finishes.
    _applying = false;
    transitionState = "idle";
    transitionMode = "";
    errorText = "Switch to " + (mode || "mode").toUpperCase()
      + " timed out after 15s — the controller did not report back."
      + " Check `sudo " + binPath + " doctor`.";
    console.warn("ModeService: " + errorText);
    _readState();
  }

  function cycleMode() {
    var idx = modes.indexOf(currentMode);
    var nxt = idx === -1 || idx >= modes.length - 1 ? modes[0] : modes[idx + 1];
    setMode(nxt);
  }

  // ── doctor (read-only diagnostics, run on demand) ────────────────────────
  property bool doctorRunning: false
  property string doctorText: ""

  property Process doctorProc: Process {
    stdout: StdioCollector {
      onStreamFinished: _root._onDoctor(text)
    }
    stderr: StdioCollector {
      onStreamFinished: (t) => {
        if (String(t || "").trim() !== "" && _root.doctorText === "")
          _root.doctorText = String(t).trim()
      }
    }
    onExited: {
      if (_root.doctorRunning) {
        _root.doctorRunning = false
        _root.doctorTimer.stop()
        if (_root.doctorText === "")
          _root.doctorText = "doctor produced no output"
      }
    }
  }

  property Timer doctorTimer: Timer {
    interval: 25000
    repeat: false
    onTriggered: {
      if (!_root.doctorRunning) return
      _root.doctorRunning = false
      _root.doctorProc.running = false
      _root.doctorText = "doctor timed out after 25s — a sensor or service is not responding."
    }
  }

  function runDoctor() {
    if (doctorRunning) return;
    doctorRunning = true;
    doctorText = "";
    doctorProc.command = [binPath, "doctor"];
    doctorProc.running = true;
    doctorTimer.restart();
  }

  function _onDoctor(text) {
    doctorTimer.stop();
    doctorRunning = false;
    var lines = String(text || "").split("\n");
    var clean = [];
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim() !== "")
        clean.push(lines[i].replace(/\s+$/, ""));
    }
    // The page has room for a short excerpt, and a full report buries the
    // useful part under swapon tables and unit states. Keep the lines that
    // answer "is this reading the right sensor / did anything fail", and fall
    // back to the tail when a run produced none of them.
    var keys = ["===", "state:", "cpu temp", "igpu", "fan", "ac ", "battery",
      "cpu_temp(", "STALE", "MISSING", "not installed", "failed", "driver:",
      "governor:", "present:"];
    var picked = [];
    for (var j = 0; j < clean.length; j++) {
      var l = clean[j].toLowerCase();
      for (var k = 0; k < keys.length; k++) {
        if (l.indexOf(keys[k]) >= 0) {
          picked.push(clean[j]);
          break;
        }
      }
    }
    doctorText = (picked.length > 0 ? picked : clean.slice(-6)).slice(0, 14).join("\n");
  }

  // ── auto mode preference ────────────────────────────────────────────────
  readonly property string autoPath: (Quickshell.env("HOME") || "") + "/.config/quickshell/mode-auto.json"

  property FileView autoLoader: FileView {
    path: _root.autoPath
    watchChanges: false
    onLoaded: {
      try {
        // FileView.text is a method in this Quickshell version, not a property.
        var t = (text() || "").trim()
        if (t) {
          var d = JSON.parse(t)
          _root._readingAuto = true
          _root.autoMode = d && d["autoMode"] === true
          _root._readingAuto = false
        }
      } catch (e) {
        console.warn("ModeService: unreadable auto preference")
      }
    }
    onLoadFailed: _root.autoMode = false
  }

  property Process autoWriter: Process {
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
  }

  function saveAuto() {
    try {
      var b64 = Qt.btoa(JSON.stringify({ autoMode: autoMode }))
      autoWriter.command = [
        "sh", "-c",
        "mkdir -p \"$HOME/.config/quickshell\" && echo '" + b64 + "' | base64 -d > \"$HOME/.config/quickshell/mode-auto.json\""
      ]
      autoWriter.running = false
      autoWriter.running = true
    } catch (e) {
      console.warn("ModeService: saveAuto:", e)
    }
  }

  onAutoModeChanged: if (!_readingAuto) saveAuto()

  // Act only on a power-source transition, never while a switch is running
  // and never immediately after the user picked a mode by hand.
  property Connections powerWatch: Connections {
    target: _root.monitor
    function onAcPoweredChanged() {
      if (!_root.autoMode || _root._applying)
        return
      if (Date.now() / 1000 - _root.lastManualSwitch < 10)
        return
      var want = _root.monitor.acPowered ? "balanced" : "silent"
      if (want !== _root.currentMode)
        _root.setMode(want, true)
    }
  }
  function timeString(ts) {
    if (!ts) return "—";
    return new Date(ts * 1000).toLocaleTimeString(Qt.locale(), "HH:mm:ss");
  }

  readonly property string lastChangeString: timeString(lastChange)
  readonly property string thermalSinceString: thermalSince > 0 ? timeString(thermalSince) : "—"

  Component.onCompleted: {
    _readState();
    autoLoader.reload();
  }
}
