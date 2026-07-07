import Quickshell
import Quickshell.Io
import QtQuick

QtObject {
  id: _root

  property real temperature: 0
  property int weatherCode: -1
  property string city: ""
  property bool loading: false

  property string lat: ""
  property string lon: ""
  property string cityOverride: ""

  property Timer pollTimer: Timer {
    interval: 300000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: fetchWeather()
  }

  property Process _proc: Process {
    command: [Quickshell.shellPath("scripts/weather.sh")]
    running: false
    environment: (function() {
      var env = {};
      if (_root.lat) env.WEATHER_LAT = _root.lat;
      if (_root.lon) env.WEATHER_LON = _root.lon;
      if (_root.cityOverride) env.WEATHER_CITY = _root.cityOverride;
      return env;
    })()
    stdout: StdioCollector {
      onStreamFinished: {
        _root.loading = false
        var out = this.text.trim()
        if (out.length > 0) {
          try {
            var d = JSON.parse(out)
            _root.temperature = d.temp
            _root.weatherCode = d.code
            _root.city = d.city || ""
          } catch (e) {
            console.error("weather parse error:", e)
          }
        }
      }
    }
  }

  function fetchWeather() {
    _root.loading = true
    _proc.running = true
  }

  function iconForCode(code) {
    if (code === 0) return "󰖨";
    if (code <= 3) return "󰖕";
    if (code <= 48) return "󰖋";
    if (code <= 57) return "󰖗";
    if (code <= 67) return "󰖖";
    if (code <= 77) return "󰖘";
    if (code <= 82) return "󰖖";
    if (code >= 95) return "󰖓";
    return "󰖙";
  }
}
