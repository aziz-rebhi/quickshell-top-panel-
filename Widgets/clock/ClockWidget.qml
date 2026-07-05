import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts

import "../media"
import "../status"
import "../notifications"
import "../power"
import "../wallpaper"
import "../askpass"
import "../../core"

Rectangle {
  id: clockWidget

  property bool isPinned: false
  property bool isExpanded: mouseArea.containsMouse || statusCapsule.isHovered || isPinned
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

  function volumeIcon(vol, muted) {
    if (muted || vol <= 0) return "󰝟";
    if (vol < 0.34) return "󰕿";
    if (vol < 0.67) return "󰖀";
    return "󰕾";
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
      "  sleep 0.05; " +
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

  function brightnessIcon(val) {
    if (val < 0.34) return "󰃞";
    if (val < 0.67) return "󰃟";
    return "󰃠";
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

  // --- Power menu state ---
  property bool showPowerMenu: false
  signal showPowerMenuRequested()
  property bool powerMenuHovered: powerMenuComponent ? powerMenuComponent.hovered : false
  property Timer powerMenuTimer: Timer {
    interval: 10000
    onTriggered: clockWidget.showPowerMenu = false
  }

  function powerAction(cmd) {
    var p = Qt.createQmlObject('import QtQuick; import Quickshell.Io; Process { command: ' + JSON.stringify(cmd) + ' }', clockWidget);
    p.exited.connect(function() { p.destroy() });
    p.running = true;
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

  // --- Notification lifecycle ---
  onLatestNotificationDataChanged: {
    if (_ready && latestNotificationData) {
      if (showPowerMenu) showPowerMenu = false;
      if (showAppLauncher) showAppLauncher = false;
      if (showWallpaperMenu) showWallpaperMenu = false;
      if (notifUnpinTimer) notifUnpinTimer.restart();
    }
  }

  readonly property bool notifHovered: (mouseArea && mouseArea.containsMouse) || (statusCapsule && statusCapsule.isHovered) || (notifBanner && notifBanner.bannerHovered)

  onNotifHoveredChanged: {
    if (notifHovered && notifUnpinTimer.running) {
      notifUnpinTimer.stop();
    } else if (!notifHovered && _ready && latestNotificationData) {
      notifUnpinTimer.restart();
    }
  }

  Timer {
    id: notifUnpinTimer
    interval: 3500
    onTriggered: {
      clockWidget.notifBannerDismissed(clockWidget.latestNotificationData);
    }
  }

  Timer {
    id: revertTimer
    interval: 2000
    onTriggered: mode = "default"
  }

  // --- Layout ---
  MediaService { id: media }

  // --- Askpass dialog state ---
  property var askpassSvc: null
  property bool showAskpass: askpassSvc && askpassSvc.pendingRequest !== null

  // Size changes are the core of the Dynamic Island morph.
  // Regular expanded = 64×540; notification/power = 130×480; app launcher = 240×480; askpass = 200×480; collapsed = 36×auto.
  height: showAppLauncher ? 240 : (showWallpaperMenu ? 300 : (showAskpass ? 200 : (latestNotificationData || showPowerMenu ? 130 : (isExpanded ? 64 : 36))))
  width: showWallpaperMenu ? 640 : (showAskpass || latestNotificationData || showPowerMenu || showAppLauncher ? 480 : (isExpanded ? 540 : (mode !== "default" ? indicatorRow.implicitWidth + 86 : collapsedRow.implicitWidth + 86)))
  radius: showWallpaperMenu ? 28 : (showAskpass || latestNotificationData || showPowerMenu || showAppLauncher ? 28 : (isExpanded ? 22 : 18))
  color: Theme.background

  // Elastic morph animation for regular expand/collapse
  Behavior on height { NumberAnimation { duration: 450; easing.type: Easing.OutBack } }
  Behavior on width  { NumberAnimation { duration: 450; easing.type: Easing.OutBack } }
  Behavior on radius { NumberAnimation { duration: 450; easing.type: Easing.OutBack } }

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
      if (clockWidget.isExpanded) {
        let mappedPos = mouseArea.mapToItem(expandedContent, mouse.x, mouse.y);
        let clickedItem = expandedContent.childAt(mappedPos.x, mappedPos.y);
        if (clickedItem !== null) return;
      }
      clockWidget.isPinned = !clockWidget.isPinned;
    }
  }

  // --- Collapsed: clock + cava (default) ---
  RowLayout {
    id: collapsedRow
    anchors.centerIn: parent
    spacing: media.playing ? 8 : 0

    opacity: clockWidget.isExpanded || clockWidget.mode !== "default" ? 0.0 : 1.0
    visible: opacity > 0.0
    Behavior on opacity { NumberAnimation { duration: 200 } }

    Item {
      id: visualizerContainer
      Layout.alignment: Qt.AlignVCenter
      property real targetWidth: media.playing ? 14 : 0
      Layout.preferredWidth: targetWidth
      Layout.preferredHeight: 12
      clip: true

      Behavior on targetWidth { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        height: 12

        Rectangle { width: 2; height: Math.min(12, media.bars[0]); radius: 1; color: Theme.primary; anchors.bottom: parent.bottom }
        Rectangle { width: 2; height: Math.min(12, media.bars[1]); radius: 1; color: Theme.primary; anchors.bottom: parent.bottom }
        Rectangle { width: 2; height: Math.min(12, media.bars[2]); radius: 1; color: Theme.primary; anchors.bottom: parent.bottom }
        Rectangle { width: 2; height: Math.min(12, media.bars[3]); radius: 1; color: Theme.primary; anchors.bottom: parent.bottom }
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
        text: clockWidget.volumeIcon(clockWidget.volume, clockWidget.audioMuted)
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
        text: clockWidget.brightnessIcon(clockWidget.brightness)
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

    // Mode indicator
    RowLayout {
      spacing: 8
      visible: clockWidget.mode === "mode"

      Text {
        text: {
          if (!clockWidget.modeSvc) return "";
          var m = clockWidget.modeSvc.currentMode;
          if (m === "silent") return "";
          if (m === "performance") return "";
          return "";
        }
        color: {
          if (!clockWidget.modeSvc) return Theme.subtext;
          var m = clockWidget.modeSvc.currentMode;
          if (m === "silent") return Theme.tertiary;
          if (m === "performance") return Theme.error;
          return Theme.primary;
        }
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 18 }
      }

      Text {
        text: {
          if (!clockWidget.modeSvc) return "Balanced";
          var m = clockWidget.modeSvc.currentMode;
          return m.charAt(0).toUpperCase() + m.slice(1);
        }
        color: Theme.text
        font { family: "Inter"; pixelSize: 13; weight: 700 }
      }
    }

  }

  // --- Expanded content (regular) ---
  // Visible when expanded with no notification: shows media player, clock, status capsule.
  Item {
    id: expandedContent
    anchors.fill: parent
    anchors.leftMargin: 16
    anchors.rightMargin: 16

    opacity: clockWidget.isExpanded && !clockWidget.showingNotification ? 1.0 : 0.0
    visible: opacity > 0.0
    Behavior on opacity { NumberAnimation { duration: 150 } }

    MediaSection {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      trackTitle: media.title
      trackArtist: media.artist
      trackArt: media.art
      mediaState: media.mediaState
      barHeights: media.bars
    }

    Item {
      id: centerSection
      anchors.centerIn: parent

      ColumnLayout {
        id: clockView
        anchors.centerIn: parent
        spacing: 4

        Text {
          text: Qt.formatDateTime(clock.date, "HH:mm")
          color: Theme.text
          Layout.alignment: Qt.AlignHCenter
          font { family: "Inter"; pixelSize: 20; weight: 700 }
        }

        Text {
          text: Qt.formatDateTime(clock.date, "ddd, MMM d")
          color: Theme.text
          opacity: 0.5
          Layout.alignment: Qt.AlignHCenter
          font { family: "Inter"; pixelSize: 11; weight: 500 }
        }
      }
    }

    StatusCapsule {
      id: statusCapsule
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      onClicked: clockWidget.toggleControlCenter()
    }
  }

  // --- Power menu overlay ---
  PowerMenu {
    id: powerMenuComponent
    anchors.fill: parent
    visible: clockWidget.showPowerMenu
    powerAction: clockWidget.powerAction
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
