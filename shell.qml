import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

import "./Widgets/clock"
import "./controlCenter"
import "./Widgets/notifications"
import "./Widgets/launcher"
import "./Widgets/mode"
import "./core"
import "./Widgets/wallpaper"
import "./Widgets/askpass"
import "./Widgets/status"

ShellRoot {
  id: root

  property bool isControlCenterOpen: false
  property bool fullScreenActive: false

  NotificationService {
    id: notifService
  }

  PanelWindow {
    anchors { top: true; left: true; right: true }
    implicitHeight: clockItem.height + 20
    color: "transparent"

    // Fixed exclusive zone — notification banner makes the window taller
    // but keeps the clock's reservation so it floats over apps, not pushes them.
    WlrLayershell.exclusiveZone: 56
    // Exclusive keyboard grab when the askpass dialog is open — enables the
    // password field to receive keystrokes without requiring a click first.
    WlrLayershell.keyboardFocus: clockItem.showAskpass || clockItem.showAppLauncher ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
      anchors.fill: parent
      enabled: clockItem.showPowerMenu || clockItem.showWallpaperMenu || clockItem.showColorPicker || clockItem.showAppLauncher
      onClicked: {
        clockItem.showPowerMenu = false;
        clockItem.showWallpaperMenu = false;
        clockItem.showAppLauncher = false;
        if (clockItem.showColorPicker && wallpaperSvc)
          wallpaperSvc.cancelPick();
      }
    }

    Clock {
      id: clockItem
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: 10

      opacity: !isControlCenterOpen ? 1 : 0
      visible: opacity > 0

      Behavior on opacity {
        NumberAnimation { duration: 300; easing.type: Easing.OutQuart }
      }

      latestNotification: notifService.latestNotification
      latestNotificationData: notifService.latestNotificationData
      storedNotifications: notifService.storedNotifications
      appLauncherSvc: appLauncherService
      onNotifDismissed: (notifRef) => notifService.dismissBanner(notifRef)
      onNotifBannerDismissed: (notifRef) => notifService.dismissBanner(notifRef)

      onToggleControlCenter: isControlCenterOpen = true

      wallpaperSvc: wallpaperSvc
      modeSvc: modeSvc
      askpassSvc: askpassSvc
      fullScreenActive: root.fullScreenActive
    }
  }

  // Instant plug/unplug + battery events via udev (no polling delay).
  Process {
    id: udevBattery
    running: true
    command: ["sh", "-c",
      "udevadm monitor --udev --property --subsystem-match=power_supply | while IFS= read -r line; do " +
      "  case \"$line\" in " +
      "    \"POWER_SUPPLY_ONLINE=1\")   echo \"P\";; " +
      "    \"POWER_SUPPLY_ONLINE=0\")   echo \"U\";; " +
      "    \"POWER_SUPPLY_STATUS=Charging\"|\"POWER_SUPPLY_STATUS=Full\") echo \"C\";; " +
      "    \"POWER_SUPPLY_STATUS=Discharging\") echo \"D\";; " +
      "    \"POWER_SUPPLY_CAPACITY=\"*) echo \"B=${line#POWER_SUPPLY_CAPACITY=}\";; " +
      "  esac; " +
      "done"
    ]
    stdout: SplitParser {
      onRead: (data) => {
        var l = data.trim();
        if (l.length === 1) {
          if (l === "P" || l === "C") { if (!StatusService.charging) StatusService.charging = true; }
          else if (l === "U" || l === "D") { if (StatusService.charging) StatusService.charging = false; }
        } else if (l.length > 2 && l.charAt(0) === 'B' && l.charAt(1) === '=') {
          var cap = parseInt(l.substring(2));
          if (!isNaN(cap)) StatusService.battery = cap;
        }
      }
    }
  }

  Process {
    id: fullscreenProc
    running: true
    command: ["sh", "-c",
      "while true; do " +
      "  s=$(hyprctl activewindow -j 2>/dev/null | grep -o '\"fullscreen\": *[0-9]*' | head -1 | grep -o '[0-9]*$'); " +
      "  [ -z \"$s\" ] && s=0; " +
      "  echo \"f=$s\"; " +
      "  sleep 0.5; " +
      "done"
    ]
    stdout: SplitParser {
      onRead: (data) => {
        var line = data.trim();
        if (line.length < 3 || line.charAt(0) !== 'f' || line.charAt(1) !== '=') return;
        var val = parseInt(line.substring(2));
        root.fullScreenActive = !isNaN(val) && val >= 2;
      }
    }
  }

  Process {
    id: ipcChecker
    running: true
    command: ["sh", "-c",
      "while true; do " +
      "  out=''; " +
      "  test -f /tmp/qs-power-menu && rm /tmp/qs-power-menu && out=\"${out}p\"; " +
      "  test -f /tmp/qs-app-launcher && rm /tmp/qs-app-launcher && out=\"${out}a\"; " +
      "  test -f /tmp/qs-wallpaper && rm /tmp/qs-wallpaper && out=\"${out}w\"; " +
      "  test -f /tmp/qs-mode-cycle && rm /tmp/qs-mode-cycle && out=\"${out}m\"; " +
      "  test -f /tmp/qs-toggle-cc && rm /tmp/qs-toggle-cc && out=\"${out}c\"; " +
      "  if [ -n \"$out\" ]; then echo \"$out\"; fi; " +
      "  sleep 0.5; " +
      "done"
    ]
    stdout: SplitParser {
      onRead: (data) => {
        var flags = data.trim()
        // Mutual exclusion: power menu and app launcher cannot both be open.
        // If both flags arrive in the same poll, power menu wins.
        if (flags.indexOf("p") >= 0) {
          if (clockItem.showColorPicker) wallpaperSvc.cancelPick();
          clockItem.showAppLauncher = false;
          clockItem.showWallpaperMenu = false;
          clockItem.showPowerMenu = true;
        } else if (flags.indexOf("a") >= 0) {
          if (clockItem.showColorPicker) wallpaperSvc.cancelPick();
          clockItem.showPowerMenu = false;
          clockItem.showWallpaperMenu = false;
          clockItem.showAppLauncher = true;
        }
        if (flags.indexOf("w") >= 0) {
          clockItem.showPowerMenu = false;
          clockItem.showAppLauncher = false;
          clockItem.showWallpaperMenu = !clockItem.showWallpaperMenu;
        }
        if (flags.indexOf("m") >= 0) {
          modeSvc.cycleMode();
          clockItem.showModeIndicator();
        }
        if (flags.indexOf("c") >= 0)
          isControlCenterOpen = !isControlCenterOpen;
      }
    }
  }
  PanelWindow {
    anchors { top: true; left: true; right: true }
    implicitHeight: 70
    color: "transparent"
    visible: batteryPopup.opacity > 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: 0
    WlrLayershell.focusable: false

    BatteryPopup {
      id: batteryPopup
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: 12
    }
  }

  // Battery event controller: low warnings (30 / 15) + plug/unplug transitions.
  Item {
    id: batteryController
    visible: false

    property int battery: StatusService.battery
    property bool charging: StatusService.charging
    property bool _chargingInit: false
    property bool _warned30: false
    property bool _warned15: false

    // Let StatusService settle after boot before treating a change as a transition.
    Timer {
      interval: 1500
      running: true
      repeat: false
      onTriggered: batteryController._chargingInit = true
    }

    onBatteryChanged: {
      if (!root.fullScreenActive) return;
      if (batteryController.charging || batteryController.battery > 30) {
        batteryController._warned30 = false;
        batteryController._warned15 = false;
        return;
      }
      if (batteryController.battery <= 15 && !batteryController._warned15) {
        batteryController._warned15 = true;
        batteryPopup.notify("low15");
      } else if (batteryController.battery <= 30 && !batteryController._warned30) {
        batteryController._warned30 = true;
        batteryPopup.notify("low30");
      }
    }

    onChargingChanged: {
      if (!root.fullScreenActive) return;
      if (!batteryController._chargingInit) return;
      if (batteryController.charging)
        batteryPopup.notify("charging");
      else
        batteryPopup.notify("unplug");
    }
  }

  // Watch colors.json generated by matugen → push new values into Theme singleton
  FileView {
    id: themeFileWatcher
    path: Quickshell.shellPath("core/colors.json")
    watchChanges: true
    onLoaded: applyColors()
    onTextChanged: applyColors()

    function applyColors() {
      var t = text().trim()
      if (t.length < 10) return
      try {
        var c = JSON.parse(t)
        // Neutral chrome surfaces stay fixed dark; only accents follow matugen.
        if (c.primary) Theme.primary = c.primary
        if (c.primaryFg) Theme.primaryFg = c.primaryFg
        if (c.secondary) Theme.secondary = c.secondary
        if (c.tertiary) Theme.tertiary = c.tertiary
        if (c.error) Theme.error = c.error
      } catch (e) {
        console.error("theme colors parse error:", e)
      }
    }
  }

  WallpaperService { id: wallpaperSvc }

  AppLauncherService { id: appLauncherService
 }

  ModeService { id: modeSvc }

  AskpassService { id: askpassSvc }

  Shortcut {
    sequences: ["Alt+F5"]
    onActivated: { modeSvc.cycleMode(); clockItem.showModeIndicator(); }
    context: Qt.ApplicationShortcut
  }

  Shortcut {
    sequences: ["Alt+C"]
    onActivated: isControlCenterOpen = !isControlCenterOpen
    context: Qt.ApplicationShortcut
  }

  ControlCenter {
    isOpen: isControlCenterOpen
    modeSvc: modeSvc
    storedNotifications: notifService.storedNotifications
    doNotDisturb: notifService.doNotDisturb
    onDndToggled: (val) => notifService.doNotDisturb = val
    onDismissNotif: (notifRef) => notifService.dismissNotif(notifRef)
    onClearNotifs: notifService.clearAll()
    onCloseRequested: isControlCenterOpen = false
  }
}
