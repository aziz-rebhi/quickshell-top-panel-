import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

import "../media"
import "../status"
import "../notifications"
import "../power"
import "../launcher"
import "../wallpaper"
import "../askpass"
import "../../core"

Rectangle {
  id: clockWidget

  property bool isPinned: false
  property bool isExpanded: mouseArea.containsMouse || isPinned
  signal toggleControlCenter()

  // --- Morph mode ---
  property string mode: "default"
  property bool _ready: false

  Timer {
    interval: 1000; running: true; repeat: false
    onTriggered: {
      _ready = true;
      if (latestNotificationData && notifUnpinTimer)
        notifUnpinTimer.restart();
    }
  }

  // --- Audio ---
  readonly property PwNode audioSink: Pipewire.defaultAudioSink
  readonly property bool audioMuted: !!audioSink?.audio?.muted
  readonly property real volume: Math.min(1, Math.max(0, audioSink?.audio?.volume ?? 0))

  PwObjectTracker {
    objects: clockWidget.audioSink ? [clockWidget.audioSink] : []
  }

  onVolumeChanged: {
    if (_ready && !clockWidget.isExpanded) {
      mode = "volume";
      revertTimer.restart();
    }
  }

  onAudioMutedChanged: {
    if (_ready && !clockWidget.isExpanded) {
      mode = "volume";
      revertTimer.restart();
    }
  }

  // --- Combined polling: brightness, caps lock, num lock ---
  property real brightness: 0
  property bool capsLock: false
  property bool numLock: false

  property Process pollProc: Process {
    command: [
      "sh", "-c",
      "while true; do " +
      "  b=$(brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%' || echo 0); " +
      "  c=$(cat /sys/class/leds/*capslock*/brightness 2>/dev/null | head -1 || echo 0); " +
      "  n=$(cat /sys/class/leds/*numlock*/brightness 2>/dev/null | head -1 || echo 0); " +
      "  echo \"b=$b\"; echo \"c=$c\"; echo \"n=$n\"; " +
      "  sleep 1; " +
      "done"
    ]
    running: true
    stdout: SplitParser {
      onRead: (data) => {
        var line = data.trim();
        if (line.length < 2 || line.charAt(1) !== '=') return;
        var val = line.substring(2);
        if (line.charAt(0) === 'b') {
          var pct = parseInt(val);
          if (!isNaN(pct)) clockWidget.brightness = Math.max(0, Math.min(1, pct / 100));
        } else if (line.charAt(0) === 'c') {
          clockWidget.capsLock = val.trim() === "1";
        } else if (line.charAt(0) === 'n') {
          clockWidget.numLock = val.trim() === "1";
        }
      }
    }
  }

  onBrightnessChanged: {
    if (_ready && !clockWidget.isExpanded) {
      mode = "brightness";
      revertTimer.restart();
    }
  }

  onNumLockChanged: {
    if (_ready && !clockWidget.isExpanded) {
      mode = "numlock";
      revertTimer.restart();
    }
  }

  onCapsLockChanged: {
    if (_ready && !clockWidget.isExpanded) {
      mode = "capslock";
      revertTimer.restart();
    }
  }

  // --- Battery state (low warning + plug/unplug) ---
  property bool fullScreenActive: false
  property int batteryPercent2: StatusService.battery
  property bool batteryCharging2: StatusService.charging
  property bool _batteryWarned30: false
  property bool _batteryWarned15: false
  property bool _prevCharging: false
  property bool _prevChargingInit: false

  Timer {
    id: batteryModeTimer
    interval: 6000
    onTriggered: clockWidget.mode = "default"
  }

  Timer {
    id: batteryInitTimer
    interval: 1500
    running: true
    repeat: false
    onTriggered: {
      clockWidget._prevChargingInit = true;
      clockWidget._prevCharging = StatusService.charging;
    }
  }

  onBatteryPercent2Changed: {
    if (!_ready || clockWidget.isExpanded || clockWidget.fullScreenActive) return;
    if (clockWidget.batteryCharging2 || clockWidget.batteryPercent2 > 30) {
      clockWidget._batteryWarned30 = false;
      clockWidget._batteryWarned15 = false;
      return;
    }
    if (clockWidget.batteryPercent2 <= 15 && !clockWidget._batteryWarned15) {
      clockWidget._batteryWarned15 = true;
      clockWidget.mode = "batteryCritical";
      batteryModeTimer.restart();
    } else if (clockWidget.batteryPercent2 <= 30 && !clockWidget._batteryWarned30) {
      clockWidget._batteryWarned30 = true;
      clockWidget.mode = "battery";
      batteryModeTimer.restart();
    }
  }

  onBatteryCharging2Changed: {
    if (!_ready || clockWidget.isExpanded || clockWidget.fullScreenActive) return;
    if (!clockWidget._prevChargingInit) return;
    if (clockWidget._prevCharging === clockWidget.batteryCharging2) return;
    clockWidget._prevCharging = clockWidget.batteryCharging2;
    clockWidget.mode = "charging";
    batteryModeTimer.restart();
  }

  // --- Power menu state ---
  property bool showPowerMenu: false
  signal showPowerMenuRequested()
  property bool powerMenuHovered: powerMenuComponent ? powerMenuComponent.hovered : false
  property Timer powerMenuTimer: Timer {
    interval: 10000
    onTriggered: clockWidget.showPowerMenu = false
  }

  function powerAction(cmd) {
    RunProcess.run(cmd, clockWidget);
    clockWidget.showPowerMenu = false;
  }

  // --- Mode indicator ---
  property var modeSvc: null
  function showModeIndicator() {
    if (_ready && !isExpanded) {
      mode = "mode";
      revertTimer.restart();
    }
  }

  // --- App launcher state ---
  property bool showAppLauncher: false
  property bool appLauncherHovered: false
  property var appLauncherSvc: null
  property Timer appLauncherTimer: Timer {
    interval: 15000
    onTriggered: clockWidget.showAppLauncher = false
  }

  // --- Wallpaper menu state ---
  property bool showWallpaperMenu: false
  property bool wallpaperMenuHovered: false
  property var wallpaperSvc: null
  property Timer wallpaperMenuTimer: Timer {
    interval: 20000
    onTriggered: clockWidget.showWallpaperMenu = false
  }

  // --- Color picker state ---
  property bool showColorPicker: false
  property var colorPickColors: []
  property bool colorPickLoading: false
  property Timer colorPickerTimer: Timer {
    interval: 30000
    onTriggered: {
      if (clockWidget.wallpaperSvc)
        clockWidget.wallpaperSvc.applyDefaultColor()
    }
  }

  // --- Notification state ---
  // Set from shell.qml via the latestNotification property binding.
  // When non-null, the island auto-expands to show the Dynamic Island banner.
  property var latestNotification: null
  property var latestNotificationData: null
  property var storedNotifications: []
  signal notifDismissed(var notifRef)
  signal notifBannerDismissed(var notifRef)

  // True while the notification banner is the active view
  readonly property bool showingNotification: latestNotification !== null

  // --- Power menu lifecycle ---
  onShowPowerMenuRequested: {
    showPowerMenu = true;
    if (powerMenuTimer) powerMenuTimer.restart();
  }

  onShowPowerMenuChanged: {
    if (showPowerMenu) {
      if (showWallpaperMenu) showWallpaperMenu = false;
      if (powerMenuTimer) powerMenuTimer.restart();
    }
  }

  onPowerMenuHoveredChanged: {
    if (powerMenuHovered && powerMenuTimer.running) {
      powerMenuTimer.stop();
    } else if (!powerMenuHovered && showPowerMenu) {
      powerMenuTimer.restart();
    }
  }

  // --- App launcher lifecycle ---
  onShowAppLauncherChanged: {
    if (showAppLauncher) {
      if (showPowerMenu) showPowerMenu = false;
      if (showWallpaperMenu) showWallpaperMenu = false;
      if (appLauncherTimer) appLauncherTimer.restart();
    }
  }

  onAppLauncherHoveredChanged: {
    if (appLauncherHovered && appLauncherTimer.running) {
      appLauncherTimer.stop();
    } else if (!appLauncherHovered && showAppLauncher) {
      appLauncherTimer.restart();
    }
  }

  // --- Wallpaper menu lifecycle ---
  onShowWallpaperMenuChanged: {
    if (showWallpaperMenu) {
      if (showPowerMenu) showPowerMenu = false;
      if (showAppLauncher) showAppLauncher = false;
      if (wallpaperMenuTimer) wallpaperMenuTimer.restart();
      if (wallpaperSvc) wallpaperSvc.rescan();
    }
  }

  onWallpaperMenuHoveredChanged: {
    if (wallpaperMenuHovered && wallpaperMenuTimer.running) {
      wallpaperMenuTimer.stop();
    } else if (!wallpaperMenuHovered && showWallpaperMenu) {
      wallpaperMenuTimer.restart();
    }
  }

  // --- Color picker lifecycle ---
  onShowColorPickerChanged: {
    if (showColorPicker) {
      if (showPowerMenu) showPowerMenu = false;
      if (showAppLauncher) showAppLauncher = false;
      if (showWallpaperMenu) showWallpaperMenu = false;
      if (colorPickerTimer) colorPickerTimer.restart();
    }
  }

  Connections {
    target: clockWidget.wallpaperSvc
    function onPickingColorChanged() {
      clockWidget.showColorPicker = clockWidget.wallpaperSvc
        ? clockWidget.wallpaperSvc.pickingColor : false
    }
    function onCandidateColorsChanged() {
      if (clockWidget.wallpaperSvc)
        clockWidget.colorPickColors = clockWidget.wallpaperSvc.candidateColors
    }
    function onColorPickLoadingChanged() {
      if (clockWidget.wallpaperSvc)
        clockWidget.colorPickLoading = clockWidget.wallpaperSvc.colorPickLoading
    }
    function onColorApplied() {
      clockWidget.showColorPicker = false
    }
  }

  // --- Notification lifecycle ---
  function notifShouldAutoDismiss() {
    var d = latestNotificationData;
    if (!d) return false;
    if (d.actions && d.actions.length > 0) return false;
    if (d.resident) return false;
    return true;
  }

  onLatestNotificationDataChanged: {
    if (_ready && latestNotificationData) {
      if (showPowerMenu) showPowerMenu = false;
      if (showAppLauncher) showAppLauncher = false;
      if (showWallpaperMenu) showWallpaperMenu = false;
      if (showColorPicker && wallpaperSvc) wallpaperSvc.cancelPick();
      if (notifUnpinTimer) {
        notifUnpinTimer.stop();
        if (clockWidget.notifShouldAutoDismiss())
          notifUnpinTimer.restart();
      }
    }
  }

  readonly property bool notifHovered: (mouseArea && mouseArea.containsMouse) || (notifBanner && notifBanner.bannerHovered)

  onNotifHoveredChanged: {
    if (notifHovered && notifUnpinTimer.running) {
      notifUnpinTimer.stop();
    } else if (!notifHovered && _ready && latestNotificationData && clockWidget.notifShouldAutoDismiss()) {
      notifUnpinTimer.restart();
    }
  }

  Timer {
    id: notifUnpinTimer
    interval: (clockWidget.latestNotificationData
      && clockWidget.latestNotificationData.urgency === NotificationUrgency.Critical)
      ? 6000 : 3500
    onTriggered: {
      clockWidget.notifBannerDismissed(clockWidget.latestNotificationData);
    }
  }

  Timer {
    id: revertTimer
    interval: 2000
    onTriggered: mode = "default"
  }

  // --- Day roll animation (midnight tick, makes the dates "move forward") ---
  property int dayRollY: 0
  Behavior on dayRollY { NumberAnimation { duration: 280; easing.type: Easing.OutQuart } }
  property string lastDayKey: ""

  Connections {
    target: clock
    function onDateChanged() {
      var key = Qt.formatDateTime(clock.date, "yyyy-MM-dd");
      if (clockWidget.lastDayKey === "") {
        clockWidget.lastDayKey = key;
        return;
      }
      if (clockWidget.lastDayKey !== key) {
        clockWidget.lastDayKey = key;
        clockWidget.dayRollY = -6;
        dayRollTimer.restart();
      }
    }
  }

  Timer {
    id: dayRollTimer
    interval: 620
    onTriggered: clockWidget.dayRollY = 0
  }

  // --- Layout ---
  // MediaService is a pragma Singleton (shared with ControlCenter)

  // --- Askpass dialog state ---
  property var askpassSvc: null
  property bool showAskpass: askpassSvc && askpassSvc.pendingRequest !== null

  // Size changes are the core of the Dynamic Island morph.
  // Regular expanded = 64×540; notification/power = 130×480; app launcher = 240×480; askpass = 200×480; collapsed = 36×auto.
  height: showAppLauncher ? 240 : (showWallpaperMenu ? 300 : (showAskpass ? 200 : (showColorPicker ? 130 : (latestNotificationData ? (notifBanner ? notifBanner.bannerHeight + 16 : 144) : (showPowerMenu ? 130 : (isExpanded ? 116 : 36))))))
  width: showWallpaperMenu ? 640 : (showAskpass || showColorPicker || latestNotificationData || showPowerMenu || showAppLauncher ? 480 : (isExpanded ? 500 : (mode !== "default" ? indicatorRow.implicitWidth + 86 : collapsedRow.implicitWidth + 86)))
  radius: showColorPicker ? 28 : (showWallpaperMenu ? 28 : (showAskpass || latestNotificationData || showPowerMenu || showAppLauncher ? 28 : (isExpanded ? 22 : 18)))
  color: Theme.background

  // Elastic morph animation for regular expand/collapse
  Behavior on height { NumberAnimation { duration: 450; easing.type: Easing.OutQuart } }
  Behavior on width  { NumberAnimation { duration: 450; easing.type: Easing.OutQuart } }
  Behavior on radius { NumberAnimation { duration: 450; easing.type: Easing.OutQuart } }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true

    onClicked: (mouse) => {
      if (clockWidget.showingNotification) return;
      if (clockWidget.showPowerMenu) {
        clockWidget.showPowerMenu = false;
        return;
      }
      if (clockWidget.showWallpaperMenu) {
        clockWidget.showWallpaperMenu = false;
        return;
      }
      if (clockWidget.showAppLauncher) return;
      clockWidget.isPinned = !clockWidget.isPinned;
    }
  }

  // --- Collapsed: clock + cava (default) ---
  RowLayout {
    id: collapsedRow
    anchors.centerIn: parent
    spacing: MediaService.playing ? 8 : 0


    opacity: clockWidget.isExpanded || clockWidget.mode !== "default" ? 0.0 : 1.0
    visible: opacity > 0.0
    Behavior on opacity { NumberAnimation { duration: 200 } }

    Item {
      id: visualizerContainer
      Layout.alignment: Qt.AlignVCenter
      property real targetWidth: MediaService.playing ? 14 : 0

      Layout.preferredWidth: targetWidth
      Layout.preferredHeight: 12
      clip: true

      Behavior on targetWidth { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        height: 12

        Rectangle { width: 2; height: Math.min(12, MediaService.bars[0]); radius: 1; color: Theme.primary; anchors.bottom: parent.bottom }
        Rectangle { width: 2; height: Math.min(12, MediaService.bars[1]); radius: 1; color: Theme.primary; anchors.bottom: parent.bottom }
        Rectangle { width: 2; height: Math.min(12, MediaService.bars[2]); radius: 1; color: Theme.primary; anchors.bottom: parent.bottom }
        Rectangle { width: 2; height: Math.min(12, MediaService.bars[3]); radius: 1; color: Theme.primary; anchors.bottom: parent.bottom }
      }
    }

    Text {
      text: Qt.formatDateTime(clock.date, "HH:mm")
      color: Theme.text
      font { family: "Inter"; pixelSize: 14; weight: 500 }
    }
  }

  // --- Collapsed: volume / brightness indicator ---
  RowLayout {
    id: indicatorRow
    anchors.centerIn: parent
    spacing: 8

    opacity: !clockWidget.isExpanded && clockWidget.mode !== "default" ? 1.0 : 0.0
    visible: opacity > 0.0
    Behavior on opacity { NumberAnimation { duration: 200 } }

    // Volume mode
    RowLayout {
      spacing: 8
      visible: clockWidget.mode === "volume"

      Text {
        text: Helpers.volumeIcon(clockWidget.volume, clockWidget.audioMuted)
        color: clockWidget.audioMuted ? Theme.subtext : Theme.primary
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 18 }
        Behavior on color { ColorAnimation { duration: 120 } }
      }

      Item {
        width: 80; height: 6
        Rectangle {
          anchors.fill: parent; radius: 3; color: Theme.border
          Rectangle {
            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
            width: parent.width * (clockWidget.audioMuted ? 0 : clockWidget.volume)
            radius: 3
            color: clockWidget.audioMuted ? Theme.border : Theme.primary
            Behavior on width { NumberAnimation { duration: 150; easing: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 120 } }
          }
        }
      }

      Text {
        text: Math.round((clockWidget.audioMuted ? 0 : clockWidget.volume) * 100) + "%"
        color: clockWidget.audioMuted ? Theme.subtext : Theme.text
        font { family: "Inter"; pixelSize: 13; weight: 700 }
        Behavior on color { ColorAnimation { duration: 120 } }
      }
    }

    // Brightness mode
    RowLayout {
      spacing: 8
      visible: clockWidget.mode === "brightness"

      Text {
        text: Helpers.brightnessIcon(clockWidget.brightness)
        color: Qt.rgba(
          0.89, 0.7 + 0.25 * clockWidget.brightness, 0.25,
          0.4 + 0.6 * clockWidget.brightness
        )
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 18 }
        Behavior on color { ColorAnimation { duration: 200 } }
      }

      Item {
        width: 80; height: 6
        Rectangle {
          anchors.fill: parent; radius: 3; color: Theme.border
          Rectangle {
            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
            width: parent.width * clockWidget.brightness
            radius: 3; color: Theme.warning
            Behavior on width { NumberAnimation { duration: 200; easing: Easing.OutCubic } }
          }
        }
      }

      Text {
        text: Math.round(clockWidget.brightness * 100) + "%"
        color: Theme.text
        font { family: "Inter"; pixelSize: 13; weight: 700 }
      }
    }

    // Caps Lock mode
    RowLayout {
      spacing: 8
      visible: clockWidget.mode === "capslock"

      Text {
        text: "󰜹"
        color: clockWidget.capsLock ? Theme.primary : Theme.subtext
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 18 }
        Behavior on color { ColorAnimation { duration: 120 } }
      }

      Text {
        text: clockWidget.capsLock ? "ON" : "OFF"
        color: clockWidget.capsLock ? Theme.text : Theme.subtext
        font { family: "Inter"; pixelSize: 13; weight: 700 }
        Behavior on color { ColorAnimation { duration: 120 } }
      }
    }

    // Num Lock mode
    RowLayout {
      spacing: 8
      visible: clockWidget.mode === "numlock"

      Text {
        text: "󰎦"
        color: clockWidget.numLock ? Theme.primary : Theme.subtext
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 18 }
        Behavior on color { ColorAnimation { duration: 120 } }
      }

      Text {
        text: clockWidget.numLock ? "ON" : "OFF"
        color: clockWidget.numLock ? Theme.text : Theme.subtext
        font { family: "Inter"; pixelSize: 13; weight: 700 }
        Behavior on color { ColorAnimation { duration: 120 } }
      }
    }

    // Battery low
    RowLayout {
      spacing: 8
      visible: clockWidget.mode === "battery"

      Text {
        text: "󰁺"
        color: Theme.error
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 18 }
      }

      Text {
        text: "Battery low"
        color: Theme.text
        font { family: "Inter"; pixelSize: 13; weight: 700 }
      }

      Text {
        text: clockWidget.batteryPercent2 + "%"
        color: Theme.error
        font { family: "Inter"; pixelSize: 13; weight: 700 }
      }
    }

    // Battery critical
    RowLayout {
      spacing: 8
      visible: clockWidget.mode === "batteryCritical"

      Text {
        text: "󰂎"
        color: Theme.error
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 18 }
      }

      Text {
        text: "Battery critical"
        color: Theme.error
        font { family: "Inter"; pixelSize: 13; weight: 700 }
      }

      Text {
        text: clockWidget.batteryPercent2 + "%"
        color: Theme.error
        font { family: "Inter"; pixelSize: 13; weight: 700 }
      }
    }

    // Charge state change (plug in / unplug)
    RowLayout {
      spacing: 8
      visible: clockWidget.mode === "charging"

      Text {
        text: clockWidget.batteryCharging2 ? "󱟩" : "󰂑"
        color: clockWidget.batteryCharging2 ? Theme.success : Theme.warning
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 18 }
      }

      Text {
        text: clockWidget.batteryCharging2 ? "Charging" : "On battery"
        color: Theme.text
        font { family: "Inter"; pixelSize: 13; weight: 700 }
      }

      Text {
        text: clockWidget.batteryPercent2 + "%"
        color: Theme.text
        font { family: "Inter"; pixelSize: 13; weight: 700 }
      }
    }

    // Mode indicator
    RowLayout {
      spacing: 8
      visible: clockWidget.mode === "mode"

      Text {
        text: {
          if (!clockWidget.modeSvc) return "";
          var m = clockWidget.modeSvc.currentMode;
          if (m === "silent") return "";
          if (m === "gaming") return "";
          if (m === "ai") return "󰋛";
          if (m === "performance") return "";
          return "";
        }
        color: {
          if (!clockWidget.modeSvc) return Theme.subtext;
          var m = clockWidget.modeSvc.currentMode;
          if (m === "silent") return Theme.tertiary;
          if (m === "gaming" || m === "ai") return Theme.error;
          if (m === "performance") return Theme.error;
          return Theme.primary;
        }
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 18 }
      }

      Text {
        text: {
          if (!clockWidget.modeSvc) return "Balanced";
          var m = clockWidget.modeSvc.currentMode;
          var names = {
            "silent": "Silent",
            "balanced": "Balanced",
            "performance": "Performance",
            "gaming": "Gaming",
            "ai": "AI"
          };
          return names[m] || "Balanced";
        }
        color: Theme.text
        font { family: "Inter"; pixelSize: 13; weight: 700 }
      }
    }

  }

  // --- Expanded content (regular) ---
  // One unified capsule: existing content on the left, large clock + date +
  // calendar strip on the right.
  Item {
    id: expandedContent
        anchors.fill: parent
    anchors.leftMargin: 30
    anchors.rightMargin: 50

    opacity: clockWidget.isExpanded && !clockWidget.showingNotification ? 1.0 : 0.0
    visible: opacity > 0.0
    Behavior on opacity { NumberAnimation { duration: 150 } }

    RowLayout {
      anchors.fill: parent
      spacing: 24

      // LEFT section (~65-70%): existing content
      ColumnLayout {
        id: leftSection
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: 10

        MediaSection {
          id: mediaSection
          Layout.alignment: Qt.AlignLeft
          clip: true
          trackTitle: MediaService.title
          trackArtist: MediaService.artist
          trackArt: MediaService.art
          mediaState: MediaService.mediaState
          barHeights: MediaService.bars
          onPreviousRequested: MediaService.previous()
          onToggleRequested: MediaService.togglePlaying()
          onNextRequested: MediaService.next()
        }
      }

      // RIGHT section (~30-35%): large clock + date + calendar strip
      ColumnLayout {
        id: clockView
        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
        spacing: 2

        Text {
          text: Qt.formatDateTime(clock.date, "HH:mm")
          color: Theme.text
          font { family: Fonts.main; pixelSize: 24; weight: Font.Bold }
          Layout.alignment: Qt.AlignHCenter
        }

        // Weekday letters as stepped podium (5 days, today peaks, dates cascade down + fade both sides)
        Row {
          Layout.alignment: Qt.AlignRight
          Layout.topMargin: 3
          spacing: 3
          transform: Translate { y: clockWidget.dayRollY }

          Repeater {
            model: 5

            delegate: Item {
              readonly property date stepDay: {
                var base = new Date(clock.date);
                base.setDate(base.getDate() + index - 2);
                return base;
              }
              readonly property int distance: Math.abs(index - 2)
              readonly property int cellSize: [9, 7, 6][distance]
              readonly property real stepOpacity: [1.0, 0.5, 0.22][distance]
              readonly property int stepY: [-4, 0, 5][distance]
              readonly property var letters: ["S", "M", "T", "W", "T", "F", "S"]

              width: distance === 0 ? 26 : 18
              height: 12

              Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: stepY
                text: distance === 0
                  ? Qt.formatDate(stepDay, "ddd").toUpperCase()
                  : letters[stepDay.getDay()].toUpperCase()
                color: distance === 0 ? Theme.primary : Theme.text
                opacity: stepOpacity
                font { family: Fonts.main; pixelSize: cellSize; weight: distance === 0 ? Font.Bold : Font.Normal }
              }
            }
          }
        }

        // Day numbers as stepped podium (5 days, today peaks, dates cascade down + fade both sides)
        Row {
          Layout.alignment: Qt.AlignRight
          Layout.topMargin: 2
          spacing: 3
          transform: Translate { y: clockWidget.dayRollY }

          Repeater {
            model: 5

            delegate: Item {
              readonly property date stepDay: {
                var base = new Date(clock.date);
                base.setDate(base.getDate() + index - 2);
                return base;
              }
              readonly property int distance: Math.abs(index - 2)
              readonly property int cellSize: [13, 10, 9][distance]
              readonly property real stepOpacity: [1.0, 0.5, 0.22][distance]
              readonly property int stepY: [-4, 0, 5][distance]

              width: distance === 0 ? 26 : 18
              height: 18

              Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: stepY
                text: stepDay.getDate()
                color: distance === 0 ? Theme.primary : Theme.text
                opacity: stepOpacity
                font { family: Fonts.main; pixelSize: cellSize; weight: distance === 0 ? Font.Bold : Font.Normal }
              }
            }
          }
        }
      }
    }
  }

  // --- Power menu overlay ---
  PowerMenu {
    id: powerMenuComponent
    anchors.fill: parent
    visible: clockWidget.showPowerMenu
    powerAction: clockWidget.powerAction
  }

  // --- App launcher overlay ---
  AppLauncher {
    id: appLauncherOverlay
    anchors.fill: parent
    visible: clockWidget.showAppLauncher
    appService: clockWidget.appLauncherSvc
    onCloseRequested: clockWidget.showAppLauncher = false
    onHoveredChanged: clockWidget.appLauncherHovered = hovered
  }

  // --- Wallpaper menu overlay ---
  Item {
    id: wallpaperMenuComponent
    anchors.fill: parent
    clip: true
    visible: clockWidget.showWallpaperMenu

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 16
      spacing: 8

      // Header
      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
          text: ""
          color: Theme.tertiary
          font { family: "JetBrainsMono Nerd Font"; pixelSize: 16 }
        }

        Text {
          text: "Wallpapers"
          color: Theme.text
          font { family: "Inter"; pixelSize: 14; weight: Font.Bold }
          Layout.fillWidth: true
        }

        Text {
          text: "✕"
          color: Theme.text
          opacity: 0.5
          font.pixelSize: 13
          MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: clockWidget.showWallpaperMenu = false
          }
        }
      }

      // Grid
      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 12
        color: Theme.container
        clip: true

        WallpaperGrid {
          anchors.fill: parent
          anchors.margins: 8
          wallpaperModel: clockWidget.wallpaperSvc ? clockWidget.wallpaperSvc.wallpapers : []
          wallService: clockWidget.wallpaperSvc
          onWallpaperChosen: function(path) {
            clockWidget.showWallpaperMenu = false
          }
        }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            propagateComposedEvents: true
            onEntered: clockWidget.wallpaperMenuHovered = true
            onExited: clockWidget.wallpaperMenuHovered = false
          }
      }
    }
  }

  ColorPicker {
    id: colorPickerOverlay
    anchors.centerIn: parent
    colors: clockWidget.colorPickColors
    loading: clockWidget.colorPickLoading
    wallService: clockWidget.wallpaperSvc
    onDismissed: {
      if (clockWidget.wallpaperSvc)
        clockWidget.wallpaperSvc.cancelPick()
    }
    visible: clockWidget.showColorPicker
  }

  NotificationBanner {
    id: notifBanner
    anchors.centerIn: parent

    notification: clockWidget.latestNotification
    notificationData: clockWidget.latestNotificationData

    onDismissed: (notifRef) => {
      if (clockWidget.notifUnpinTimer)
        clockWidget.notifUnpinTimer.stop();
      clockWidget.notifDismissed(notifRef);
    }
  }

  PasswordAskpassDialog {
    id: askpassDialog
    anchors.centerIn: parent

    promptText: clockWidget.showAskpass && clockWidget.askpassSvc ? clockWidget.askpassSvc.pendingRequest.prompt : ""
    fifoPath: clockWidget.showAskpass && clockWidget.askpassSvc ? clockWidget.askpassSvc.pendingRequest.fifoPath : ""

    onSubmitted: (password) => { if (clockWidget.askpassSvc) clockWidget.askpassSvc.submit(password); }
    onCancelled: { if (clockWidget.askpassSvc) clockWidget.askpassSvc.cancel(); }
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }
}