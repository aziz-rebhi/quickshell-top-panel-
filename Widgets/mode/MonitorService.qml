import QtQuick
import Quickshell.Io

/*
 * Live hardware monitor for the Performance Control Center.
 *
 * Runs a single short-lived shell probe every `intervalMs` and parses
 * `key=value` lines. Every value is pulled from a real Linux interface
 * (sysfs hwmon, /proc, nvidia-smi, nbfc). Sensors that cannot be read
 * are exposed as `null` / explicit availability flags — never invented.
 */

QtObject {
  id: root

  property int intervalMs: 2000

  // CPU
  property string cpuName: ""
  property int cpuFreqMHz: 0
  property int cpuTemp: 0
  property int cpuUsage: 0
  property bool cpuAvailable: false

  // GPU (NVIDIA dGPU)
  property string gpuName: ""
  property int gpuUsage: 0
  property int gpuTemp: 0
  property int vramUsedMB: 0
  property int vramTotalMB: 0
  property real gpuPowerW: 0
  property bool gpuAvailable: false

  // iGPU (AMD)
  property int igpuTemp: 0
  property bool igpuAvailable: false

  // Memory
  property real memTotalGiB: 0
  property real memAvailGiB: 0
  property int memUsage: 0

  // Fan / cooling
  property int fanRpm: 0
  property real fanPct: -1 // -1 = no reading
  property bool fanAvailable: false

  // Power
  property bool acPowered: true
  property int batCap: -1
  property string batStatus: ""

  property string lastProbe: ""

  readonly property real _mbToGiB: 1024

  property Process probeProc: Process {
    running: true
    stdout: StdioCollector {
      onStreamFinished: root._onProbe(text)
    }
  }

  // First-run: static identifiers (cpu model, gpu model) — only once.
  property Process namesProc: Process {
    stdout: StdioCollector {
      onStreamFinished: root._onNames(text)
    }
  }

  readonly property string namesScript:
    "grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs;" +
    "nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null;"

  readonly property string probeScript:
    "cput=$(cat /sys/class/hwmon/hwmon5/temp1_input 2>/dev/null || echo 0);" +
    "igput=$(cat /sys/class/hwmon/hwmon4/temp1_input 2>/dev/null || echo 0);" +
    "freq=$(awk '{s+=$1} END{if(NR) printf \"%.0f\", s/NR}' " +
    "/sys/devices/system/cpu/cpufreq/policy*/scaling_cur_freq 2>/dev/null || echo 0);" +
    "st=$(awk '/^cpu /{print ($2+$3+$4+$5+$6+$7+$8) \" \" ($5+$6)}' /proc/stat);" +
    "mtot=$(awk '/MemTotal/{print $2}' /proc/meminfo);" +
    "mavail=$(awk '/MemAvailable/{print $2}' /proc/meminfo);" +
    "fr1=$(cat /sys/class/hwmon/hwmon6/fan1_input 2>/dev/null || echo 0);" +
    "fr2=$(cat /sys/class/hwmon/hwmon6/fan2_input 2>/dev/null || echo 0);" +
    "ac=$(cat /sys/class/power_supply/ACAD/online 2>/dev/null || echo 0);" +
    "bc=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo -1);" +
    "bs=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null | tr -d '\n');" +
    "nv=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw " +
    "--format=csv,noheader,nounits 2>/dev/null | tr -d '\n');" +
    "fps=$(nbfc status 2>/dev/null | awk -F: '/Current Fan Speed/{gsub(/[ |%]/, \"\", $2); print $2}');" +
    "echo \"cput=$cput\";echo \"igput=$igput\";echo \"freq=$freq\";echo \"st=$st\";" +
    "echo \"mtot=$mtot\";echo \"mavail=$mavail\";echo \"fr1=$fr1\";echo \"fr2=$fr2\";" +
    "echo \"ac=$ac\";echo \"bc=$bc\";echo \"bs=$bs\";echo \"nv=$nv\";echo \"fps=$fps\";"

  function _runProbe() {
    probeProc.command = ["sh", "-c", root.probeScript]
    probeProc.running = true
  }

  function _runNames() {
    namesProc.command = ["sh", "-c", root.namesScript]
    namesProc.running = true
  }

  onIntervalMsChanged: _timer.restart()

  property Timer _timer: Timer {
    id: timer
    interval: root.intervalMs
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: _runProbe()
  }

  Component.onCompleted: {
    _runNames()
    _runProbe()
  }

  function _onNames(text) {
    var lines = text.split("\n")
    if (lines.length > 0 && lines[0].trim() !== "")
      cpuName = lines[0].trim()
    if (lines.length > 1 && lines[1].trim() !== "")
      gpuName = lines[1].trim()
  }

  function _onProbe(text) {
    var cur = {}
    var lines = text.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var eq = lines[i].indexOf("=")
      if (eq < 0) continue
      cur[lines[i].substring(0, eq)] = lines[i].substring(eq + 1).trim()
    }
    lastProbe = new Date().toLocaleTimeString(Qt.locale(), "HH:mm:ss")

    // CPU temp: k10temp Tctl in milli-degrees
    var ct = parseInt(cur["cput"])
    cpuAvailable = !isNaN(ct) && ct > 0
    cpuTemp = cpuAvailable ? Math.round(ct / 1000) : 0

    var it = parseInt(cur["igput"])
    igpuAvailable = !isNaN(it) && it > 0
    igpuTemp = igpuAvailable ? Math.round(it / 1000) : 0

    var fr = parseInt(cur["freq"])
    cpuFreqMHz = !isNaN(fr) && fr > 0 ? fr : 0

    // CPU usage from /proc/stat deltas
    var stParts = (cur["st"] || "").split(" ")
    if (stParts.length >= 2) {
      var total = parseInt(stParts[0])
      var idle = parseInt(stParts[1])
      if (!isNaN(total) && !isNaN(idle)) {
        cpuUsage = root._usageDelta(total, idle)
      }
    }

    var mt = parseFloat(cur["mtot"])
    var ma = parseFloat(cur["mavail"])
    if (!isNaN(mt) && mt > 0) memTotalGiB = mt / 1048576
    if (!isNaN(ma) && ma > 0) {
      memAvailGiB = ma / 1048576
      memUsage = Math.round((1 - ma / mt) * 100)
    }

    // Fans: max of the two exposed hwmon inputs (this laptop's EC reads 0)
    var f1 = parseInt(cur["fr1"])
    var f2 = parseInt(cur["fr2"])
    var rpm = Math.max(isNaN(f1) ? 0 : f1, isNaN(f2) ? 0 : f2)
    fanAvailable = rpm > 0
    fanRpm = fanAvailable ? rpm : 0

    var pct = parseFloat(cur["fps"])
    fanPct = !isNaN(pct) ? Math.min(100, Math.max(0, pct)) : -1

    var acs = parseInt(cur["ac"])
    acPowered = isNaN(acs) ? true : acs === 1
    var bcc = parseInt(cur["bc"])
    batCap = isNaN(bcc) ? -1 : bcc
    batStatus = (cur["bs"] || "").trim()

    // NVIDIA via nvidia-smi (comma list: util,temp,mem.used,mem.total,power)
    var nv = (cur["nv"] || "").trim()
    gpuAvailable = nv.length > 0
    if (gpuAvailable) {
      var v = nv.split(",")
      var gutil = parseInt(v[0])
      var gtemp = parseInt(v[1])
      var mu = parseFloat(v[2])
      var mt = parseFloat(v[3])
      var pw = parseFloat(v[4])
      gpuUsage = isNaN(gutil) ? 0 : Math.min(100, Math.max(0, gutil))
      gpuTemp = isNaN(gtemp) ? 0 : gtemp
      vramUsedMB = isNaN(mu) ? 0 : Math.round(mu)
      vramTotalMB = isNaN(mt) ? 0 : Math.round(mt)
      gpuPowerW = isNaN(pw) ? 0 : pw
    } else {
      gpuUsage = 0
      gpuTemp = 0
      vramUsedMB = 0
      vramTotalMB = 0
      gpuPowerW = 0
    }
  }

  property int _prevTotal: 0
  property int _prevIdle: 0

  function _usageDelta(total, idle) {
    var dTotal = total - root._prevTotal
    var dIdle = idle - root._prevIdle
    root._prevTotal = total
    root._prevIdle = idle
    if (root._prevTotal <= 0 || dTotal <= 0) return 0
    return Math.min(100, Math.max(0, Math.round((dTotal - dIdle) / dTotal * 100)))
  }
}