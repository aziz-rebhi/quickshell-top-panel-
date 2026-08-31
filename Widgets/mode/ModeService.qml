import Quickshell
import Quickshell.Io
import QtQuick
import "../../core"

/*
 * Thin client for the performance-mode controller (performance-mode/bin/).
 * The controller owns all policy (per-mode lever mapping) + the thermal
 * watchdog; this service only displays what it applied and forwards UI
 * requests to the CLI.
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

  readonly property real cpuTemp: _tempBuf >= 0 ? _tempBuf : 0
  property real _tempBuf: -1

  property bool _applying: false

  readonly property string statePath: "/var/lib/performance-mode/state.json"
  readonly property string binPath: Quickshell.shellPath("performance-mode/bin/performance-mode")

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

  // Temperature is sampled for display only — the watchdog lives in the controller.
  property Timer tempTimer: Timer {
    interval: 8000
    repeat: true
    running: true
    onTriggered: _root._sampleTemp()
  }

  property Process _tempProc: Process {
    command: ["sh", "-c",
      "for p in /sys/class/hwmon/hwmon*/temp1_input; do " +
      "  d=$(cat $(dirname $p)/name 2>/dev/null); " +
      "  if [ \"$d\" = \"k10temp\" ]; then cat $p; exit 0; fi; " +
      "done; " +
      "for p in /sys/class/hwmon/hwmon*/temp1_input; do cat $p; exit 0; done; " +
      "echo 0"
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        var raw = parseInt(this.text.trim());
        if (!isNaN(raw) && raw > 0) _tempBuf = raw / 1000;
      }
    }
  }

  function _sampleTemp() { _tempProc.running = true; }

  function _readState() {
    _stateProc.command = ["cat", statePath];
    _stateProc.running = true;
  }

  function _parseState(raw) {
    raw = String(raw || "").trim();
    if (!raw) return;
    try {
      var s = JSON.parse(raw);
      if (s.mode && modes.indexOf(s.mode) !== -1) {
        currentMode = s.mode;
        if (!_applying) errorText = "";
      }
    } catch (e) {
      console.warn("ModeService: invalid state file");
    }
  }

  function setMode(mode) {
    if (modes.indexOf(mode) === -1 || mode === currentMode) return;
    if (_applying) return;
    _applying = true;
    errorText = "";
    var proc = Qt.createQmlObject(
      'import QtQuick; import Quickshell.Io;' +
      'Process { command: ["' + binPath + '", "set", "' + mode + '"]; stderr: StdioCollector {} }',
      _root);
    proc.exited.connect(function(code) {
      _applying = false;
      if (code === 0) {
        currentMode = mode;
        _readState();
      } else {
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

  Component.onCompleted: {
    _sampleTemp();
    _readState();
  }
}