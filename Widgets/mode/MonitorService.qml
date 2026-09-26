import Quickshell
import Quickshell.Io
import QtQuick

/*
 * Live hardware monitor for the Performance Control Center.
 *
 * Sensor paths are never hardcoded here. hwmonN numbering is assigned in
 * driver-probe order and changes on every reboot, module reload and dock
 * attach, so `performance-mode discover --json` resolves driver name ->
 * sysfs path (k10temp/zenpower/coretemp for the CPU, amdgpu for the iGPU,
 * any hwmon exposing fan*_input, power_supply type=Mains/Battery) and the
 * probe is assembled from that. The resolver's cache is re-validated while
 * polling and re-resolved outright when reads keep failing, so a renumbered
 * hwmon bus heals itself instead of silently reporting the wrong chip.
 *
 * Every value comes from a real Linux interface (sysfs hwmon, /proc,
 * nvidia-smi, nbfc). Whatever cannot be read is exposed as an explicit
 * "unavailable" (-1, or a false *Available flag) — never invented.
 */

QtObject {
  id: root

  // Poll rate follows whether anyone is looking. Every tick spawns a probe
  // (sysfs + nvidia-smi + nbfc), so a permanently-fast poll burns CPU for
  // numbers no one is reading. ModeService drives this from page visibility
  // and from "a switch is applying".
  property bool active: true
  readonly property int activeIntervalMs: 2000
  readonly property int idleIntervalMs: 8000
  readonly property int intervalMs: active ? activeIntervalMs : idleIntervalMs

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

  // iGPU (AMD) — amdgpu exposes temperature on hwmon and load on the PCI node
  property int igpuTemp: 0
  property int igpuUsage: -1 // -1 = no reading
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

  // Rolling CPU temperature for the page sparkline (oldest -> newest, 24).
  property var tempSamples: []

  readonly property real _mbToGiB: 1024

  // ── sensor discovery ────────────────────────────────────────────────────
  readonly property string binPath: Quickshell.shellPath("performance-mode/bin/performance-mode")
  property var sensors: ({})
  property bool discovering: false
  property string discoverError: ""
  property string sensorSig: ""
  readonly property bool discovered: sensorSig !== ""

  // True when discovery found at least one real sensor; "discovered" alone
  // only means the resolver answered.
  readonly property bool sensorsOk: discovered && (
    !!sensors["cpu_temp"] || (sensors["fans"] || []).length > 0
    || (sensors["mains"] || []).length > 0 || !!sensors["battery"])

  readonly property string sensorSummary: {
    if (!discovered)
      return discoverError !== "" ? "unavailable — " + discoverError : "resolving…"
    var parts = []
    if (sensors["cpu_temp"])
      parts.push(sensors["cpu_temp_name"] || "cpu")
    if (sensors["igpu_temp"])
      parts.push(sensors["igpu_temp_name"] || "igpu")
    var fans = sensors["fans"] || []
    if (fans.length > 0)
      parts.push((sensors["fan_names"] || [])[0] || "fan")
    if (sensors["mains"] && sensors["mains"].length > 0)
      parts.push("ac")
    if (sensors["battery"])
      parts.push(sensors["battery_name"] || "battery")
    return parts.length > 0 ? parts.join(" · ") : "no sensors found"
  }

  // Consecutive probes that read nothing at all — the signal that the
  // discovered paths have gone stale and need resolving again.
  property int _probeMisses: 0

  property Process discoverProc: Process {
    stdout: StdioCollector {
      onStreamFinished: root._onDiscover(text)
    }
    stderr: StdioCollector {
      onStreamFinished: (t) => {
        var s = String(t || "").trim()
        if (s !== "")
          root.discoverError = s.split("\n").pop()
      }
    }
    onExited: root.discovering = false
  }

  function _discover() {
    if (discovering)
      return
    discovering = true
    discoverProc.command = [root.binPath, "discover", "--json"]
    discoverProc.running = true
    // A binary that cannot even start never reaches the collectors, so the
    // page would sit on "resolving…" forever. Say so instead.
    _discoverWatchdog.restart()
  }

  function _onDiscover(text) {
    discovering = false
    var raw = String(text || "").trim()
    if (raw === "") {
      _discoverRetry.running = true
      return
    }
    try {
      var c = JSON.parse(raw)
      if (!c || !c["sig"])
        return
      // Same signature = same layout, nothing to rebind. Re-validating the
      // cache on a timer therefore costs a Process and no UI churn.
      if (c["sig"] === root.sensorSig)
        return
      sensors = c
      sensorSig = c["sig"]
      discoverError = ""
      _probeMisses = 0
      _discoverRetry.running = false
      _discoverWatchdog.stop()
      _timer.restart()
    } catch (e) {
      discoverError = "unparseable resolver output"
      _discoverRetry.running = true
    }
  }

  // Re-validate on a slow cadence so a renumber that leaves the old paths
  // readable is still noticed, and retry discovery when it failed outright.
  property Timer _revalidateTimer: Timer {
    interval: root.active ? 60000 : 300000
    repeat: true
    running: root.discovered
    onTriggered: root._discover()
  }

  property Timer _discoverRetry: Timer {
    interval: 30000
    repeat: true
    running: false
    onTriggered: if (!root.discovered) root._discover()
  }

  property Timer _discoverWatchdog: Timer {
    interval: 8000
    repeat: false
    onTriggered: {
      if (root.discovered) return
      if (root.discoverError === "")
        root.discoverError = "no answer from " + root.binPath
      _discoverRetry.running = true
    }
  }

  // ── probe ───────────────────────────────────────────────────────────────
  property Process probeProc: Process {
    running: true
    stdout: StdioCollector {
      onStreamFinished: root._onProbe(text)
    }
  }

  // nbfc status talks to the EC over SMBus and can block; without a
  // watchdog one hung probe would stall every later reading.
  property Timer _probeWatchdog: Timer {
    interval: 12000
    repeat: false
    onTriggered: {
      if (probeProc.running) {
        console.warn("MonitorService: probe hung, restarting it")
        probeProc.running = false
        _runProbe()
      }
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

  readonly property string probeScript: {
    if (!root.discovered)
      return ""
    var s = root.sensors
    // cat with a fallback so a vanished path yields 0 instead of aborting
    var c = function (p) {
      return p ? "cat '" + p + "' 2>/dev/null || echo 0" : "echo 0"
    }
    var fans = s["fans"] || []
    var mains = s["mains"] || []
    var bat = s["battery"] || ""
    var cmd = []
    cmd.push("cput=$(" + c(s["cpu_temp"]) + ")")
    cmd.push("igput=$(" + c(s["igpu_temp"]) + ")")
    cmd.push("igpub=$(" + c(s["igpu_busy"]) + ")")
    // scaling_cur_freq is kHz on every cpufreq driver; emit MHz so the label
    // matches the number.
    cmd.push("freq=$(awk '{s+=$1} END{if(NR) printf \"%.0f\", s/NR/1000}' /sys/devices/system/cpu/cpufreq/policy*/scaling_cur_freq 2>/dev/null || echo 0)")
    cmd.push("st=$(awk '/^cpu /{print ($2+$3+$4+$5+$6+$7+$8) \" \" ($5+$6)}' /proc/stat)")
    cmd.push("mtot=$(awk '/MemTotal/{print $2}' /proc/meminfo)")
    cmd.push("mavail=$(awk '/MemAvailable/{print $2}' /proc/meminfo)")
    for (var i = 0; i < fans.length && i < 4; i++)
      cmd.push("fr" + (i + 1) + "=$(" + c(fans[i]) + ")")
    // Any adapter reporting online 1 means AC; several Mains nodes is normal
    // on docks, so OR them instead of trusting a single one.
    cmd.push("ac=0")
    for (var j = 0; j < mains.length; j++)
      cmd.push("v=$(" + c(mains[j]) + "); [ \"$v\" = 1 ] && ac=1")
    cmd.push("bc=$(" + c(bat ? bat + "/capacity" : "") + ")")
    cmd.push("bs=$(cat '" + (bat ? bat + "/status" : "/dev/null") + "' 2>/dev/null | tr -d '\\n')")
    cmd.push("nv=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw --format=csv,noheader,nounits 2>/dev/null | tr -d '\\n')")
    // nbfc owns the fan curve on this laptop and the EC tachometer is not
    // exposed in sysfs, so it is the authoritative live percentage.
    cmd.push("fps=$(nbfc status 2>/dev/null | awk -F: '/Current Fan Speed/{gsub(/[ |%]/, \"\", $2); print $2}')")
    var out = ["cput=$cput", "igput=$igput", "igpub=$igpub", "freq=$freq",
      "st=$st", "mtot=$mtot", "mavail=$mavail"]
    for (var k = 1; k <= Math.min(fans.length, 4); k++)
      out.push("fr" + k + "=$fr" + k)
    out.push("ac=$ac", "bc=$bc", "bs=$bs", "nv=$nv", "fps=$fps")
    // One echo per key: the parser reads key=value line by line, and a single
    // `echo a=$a; b=$b` would print only the first key and then run the rest
    // as bare assignments, which produce no output at all.
    cmd.push(out.map(function (k) { return "echo " + k }).join("; "))
    return cmd.join("; ")
  }

  function _runProbe() {
    if (!discovered || probeProc.running)
      return
    probeProc.command = ["sh", "-c", root.probeScript]
    probeProc.running = true
    _probeWatchdog.restart()
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
    running: root.discovered
    triggeredOnStart: true
    onTriggered: _runProbe()
  }

  Component.onCompleted: {
    _runNames()
    _discover()
  }

  function _onNames(text) {
    var lines = text.split("\n")
    if (lines.length > 0 && lines[0].trim() !== "")
      cpuName = lines[0].trim()
    if (lines.length > 1 && lines[1].trim() !== "")
      gpuName = lines[1].trim()
  }

  function _onProbe(text) {
    _probeWatchdog.stop()
    var cur = {}
    var lines = text.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var eq = lines[i].indexOf("=")
      if (eq < 0) continue
      cur[lines[i].substring(0, eq)] = lines[i].substring(eq + 1).trim()
    }
    lastProbe = new Date().toLocaleTimeString(Qt.locale(), "HH:mm:ss")

    // CPU temp: k10temp Tctl in milli-degrees (resolved by driver name)
    var ct = parseInt(cur["cput"])
    cpuAvailable = !isNaN(ct) && ct > 0
    cpuTemp = cpuAvailable ? Math.round(ct / 1000) : 0

    var it = parseInt(cur["igput"])
    var ib = parseInt(cur["igpub"])
    igpuUsage = !isNaN(ib) ? Math.min(100, Math.max(0, ib)) : -1
    igpuTemp = !isNaN(it) ? Math.round(it / 1000) : 0
    igpuAvailable = (!isNaN(it) && it > 0) || igpuUsage >= 0

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
    if (!isNaN(ma) && mt > 0) {
      memAvailGiB = ma / 1048576
      memUsage = Math.round((1 - ma / mt) * 100)
    }

    // Fans: highest non-zero hwmon reading. The EC tachometer on this laptop
    // is not exposed in sysfs, so 0 across the board means "no reading",
    // not "fans stopped" — nbfc supplies the live percentage instead.
    var rpm = 0
    var anyFan = false
    for (var f = 1; f <= 4; f++) {
      var fv = parseInt(cur["fr" + f])
      if (!isNaN(fv) && fv > 0) {
        anyFan = true
        if (fv > rpm) rpm = fv
      }
    }
    fanAvailable = anyFan
    fanRpm = rpm

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
      var mtot = parseFloat(v[3])
      var pw = parseFloat(v[4])
      gpuUsage = isNaN(gutil) ? 0 : Math.min(100, Math.max(0, gutil))
      gpuTemp = isNaN(gtemp) ? 0 : gtemp
      vramUsedMB = isNaN(mu) ? 0 : Math.round(mu)
      vramTotalMB = isNaN(mtot) ? 0 : Math.round(mtot)
      gpuPowerW = isNaN(pw) ? 0 : pw
    } else {
      gpuUsage = 0
      gpuTemp = 0
      vramUsedMB = 0
      vramTotalMB = 0
      gpuPowerW = 0
    }

    // Nothing at all came back: the discovered layout is probably stale
    // (hwmon renumbered). Three strikes, then resolve again.
    if (ct > 0 || mt > 0 || anyFan || gpuAvailable) {
      _probeMisses = 0
    } else {
      _probeMisses++
      if (_probeMisses >= 3) {
        _probeMisses = 0
        _discover()
      }
    }

    if (cpuAvailable) {
      var s = root.tempSamples.slice()
      s.push(cpuTemp)
      if (s.length > 24)
        s = s.slice(s.length - 24)
      root.tempSamples = s
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
