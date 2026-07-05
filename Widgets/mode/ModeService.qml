import Quickshell
import Quickshell.Io
import QtQuick

/*
 * nbfc set -s <speed> overrides the laptop's automatic temperature-based
 * fan curve with a fixed fan speed. Only nbfc set -a restores the safe
 * automatic temperature curve. The temperature watchdog below is required
 * safety logic — removing it risks silent overheating in Silent or
 * Performance mode.
 */

QtObject {
  id: _root
  property string currentMode: "balanced"
  property int tempThreshold: 85

  readonly property real cpuTemp: _tempBuf >= 0 ? _tempBuf : 0
  property real _tempBuf: -1
  property bool _applying: false

  readonly property string statePath: Quickshell.shellPath("scripts/mode-state.json")

  property FileView _stateReader: FileView {
    path: statePath
  }

  // Always poll temperature; watchdog logic is inside onStreamFinished
  property Timer tempTimer: Timer {
    interval: 8000
    repeat: true
    running: true
    onTriggered: _sampleTemp()
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
        if (!isNaN(raw) && raw > 0) {
          _tempBuf = raw / 1000;
          if (currentMode !== "balanced" && _tempBuf >= tempThreshold) {
            console.warn("ModeService: CPU " + _tempBuf + "°C >= " + tempThreshold + "°C threshold — force-reverting to balanced");
            _forceRevert();
          }
        }
      }
    }
  }

  function _sampleTemp() { _tempProc.running = true; }

  function _forceRevert() {
    currentMode = "balanced";
    var p = Qt.createQmlObject('import QtQuick; import Quickshell.Io; Process { command: ["nbfc", "set", "-a"] }', _root);
    p.exited.connect(function() { p.destroy(); });
    p.running = true;
    _saveState();
  }

  function setMode(mode) {
    if (_applying || mode === currentMode) return;
    _applying = true;

    var plan = [];
    if (mode === "silent") {
      plan.push(["sh", "-c", "powerprofilesctl set power-saver 2>/dev/null || true"]);
      plan.push(["sh", "-c", "nbfc set -s 30 2>/dev/null || true"]);
      plan.push(["sh", "-c", "supergfxctl --mode integrated 2>/dev/null || true"]);
    } else if (mode === "balanced") {
      plan.push(["sh", "-c", "powerprofilesctl set balanced 2>/dev/null || true"]);
      plan.push(["sh", "-c", "nbfc set -a 2>/dev/null || true"]);
      plan.push(["sh", "-c", "supergfxctl --mode hybrid 2>/dev/null || true"]);
    } else if (mode === "performance") {
      plan.push(["sh", "-c", "powerprofilesctl set performance 2>/dev/null || true"]);
      plan.push(["sh", "-c", "nbfc set -s 90 2>/dev/null || true"]);
      plan.push(["sh", "-c", "supergfxctl --mode hybrid 2>/dev/null || true"]);
    } else {
      _applying = false;
      return;
    }

    _execSequence(plan, function() {
      currentMode = mode;
      _applying = false;
      _saveState();
    });
  }

  function _execSequence(cmds, done) {
    var i = 0;
    function next() {
      if (i >= cmds.length) {
        if (done) done();
        return;
      }
      var p = Qt.createQmlObject(
        'import QtQuick; import Quickshell.Io; Process { command: ' + JSON.stringify(cmds[i]) + ' }', _root);
      p.exited.connect(function() {
        p.destroy();
        i++;
        next();
      });
      p.running = true;
    }
    next();
  }

  function cycleMode() {
    var order = ["silent", "balanced", "performance"];
    var idx = order.indexOf(currentMode);
    setMode(idx === -1 || idx >= order.length - 1 ? order[0] : order[idx + 1]);
  }

  function _saveState() {
    var data = JSON.stringify({ mode: currentMode });
    var p = Qt.createQmlObject(
      'import QtQuick; import Quickshell.Io; Process { command: ["sh", "-c", ' +
      JSON.stringify("mkdir -p $(dirname \"" + statePath + "\") && printf '%s\\n' \"" +
        data.replace(/\"/g, '\\"') + "\" > \"" + statePath + ".tmp\" && mv -f \"" +
        statePath + ".tmp\" \"" + statePath + "\"") +
      '] }', _root);
    p.exited.connect(function() { p.destroy(); });
    p.running = true;
  }

  Component.onCompleted: {
    _sampleTemp();

    var raw = _stateReader.text().trim();
    if (!raw) {
      currentMode = "balanced";
      _applying = false;
      return;
    }
    try {
      var s = JSON.parse(raw);
      if (s.mode === "silent" || s.mode === "performance") {
        setMode(s.mode);
      } else {
        currentMode = "balanced";
      }
    } catch(e) {
      console.warn("ModeService: invalid state file, defaulting to balanced");
      currentMode = "balanced";
      _applying = false;
    }
  }
}
