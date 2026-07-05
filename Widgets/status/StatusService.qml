import Quickshell
import Quickshell.Io
import QtQuick

QtObject {
  property int battery: 0
  property bool charging: false
  property string wifi: "Disconnected"
  property int wifiSignal: 0
  property string powerStatus: "Unknown"
  property string connType: "disconnected"

  readonly property string powerState: {
    if (powerStatus === "Charging") return "Charging";
    if (powerStatus === "Full") return "Full";
    return "Discharging";
  }

  readonly property string networkState: connType === "disconnected" ? "Disconnected" : "Connected"

  property Timer pollTimer: Timer {
    interval: 5000; running: true; repeat: true; triggeredOnStart: true
    onTriggered: { pollProc.running = true }
  }

  property Process pollProc: Process {
    command: [
      "sh", "-c",
      "cap=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1); " +
      "st=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1); " +
      "types=$(nmcli -t -f TYPE,NAME con show --active 2>/dev/null); " +
      "ssid=$(echo \"$types\" | grep '^802-11-wireless:' | cut -d: -f2 -s); " +
      "[ -z \"$ssid\" ] && ssid=$(iwgetid -r 2>/dev/null); " +
      "eth=$(echo \"$types\" | grep '^802-3-ethernet:' | cut -d: -f2 -s); " +
      "connType=disconnected; " +
      "[ -n \"$ssid\" ] && connType=wifi; " +
      "[ -z \"$ssid\" ] && [ -n \"$eth\" ] && { ssid=\"$eth\"; connType=wired; }; " +
      "[ -z \"$ssid\" ] && ssid=Disconnected; " +
      "sig=$(awk 'NR>2{if($3!=\"\"){gsub(/\\./,\"\",$3); q=$3+0; print int(q*100/70)}}' /proc/net/wireless 2>/dev/null || echo 0); " +
      "echo \"${cap:-0}\"; echo \"${st:-Unknown}\"; echo \"$ssid\"; echo \"$sig\"; echo \"$connType\""
    ]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = this.text.trim().split("\n");
        if (lines.length >= 5) {
          battery = parseInt(lines[0]) || 0;
          powerStatus = lines[1].trim();
          charging = powerStatus === "Charging" || powerStatus === "Full";
          wifi = lines[2].trim() || "Disconnected";
          wifiSignal = Math.min(100, Math.max(0, parseInt(lines[3]) || 0));
          connType = lines[4].trim() || "disconnected";
        }
      }
    }
  }
}
