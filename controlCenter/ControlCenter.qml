import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.Notifications
import "./components"
import "./pages"

import Quickshell.Bluetooth
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../Widgets/notifications"
import "../core"

PanelWindow {
    id: controlCenter
    property bool isOpen: false
    visible: isOpen

    property string page: "main"
    onIsOpenChanged: if (isOpen) page = "main"

    WlrLayershell.layer: WlrLayer.Overlay

    signal closeRequested()
    signal dismissNotif(var notifRef)
    signal clearNotifs()
    signal dndToggled(bool val)
    property bool doNotDisturb: false
    property var storedNotifications: []

    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    color: "transparent"

    // --- Audio (Pipewire) ---
    property PwNode audioSink: Pipewire.defaultAudioSink
    property PwNode audioSource: Pipewire.defaultAudioSource
    property bool audioMuted: !!audioSink?.audio?.muted
    property bool audioSourceMuted: !!audioSource?.audio?.muted
    property real audioVolume: Math.min(1, Math.max(0, audioSink?.audio?.volume ?? 0))
    property real audioSourceVolume: Math.min(1, Math.max(0, audioSource?.audio?.volume ?? 0))

    property var audioSinks: []
    property var audioSources: []

    function _addAudioNode(node) {
        if (!node || !node.ready) return;
        if (node.type === PwNodeType.AudioSink) {
            if (audioSinks.indexOf(node) !== -1) return;
            var s = audioSinks.slice();
            s.push(node);
            s.sort(function(a, b) { return (a.description || a.name || "").localeCompare(b.description || b.name || ""); });
            audioSinks = s;
        } else if (node.type === PwNodeType.AudioSource) {
            if (audioSources.indexOf(node) !== -1) return;
            var s2 = audioSources.slice();
            s2.push(node);
            s2.sort(function(a, b) { return (a.description || a.name || "").localeCompare(b.description || b.name || ""); });
            audioSources = s2;
        }
    }

    function _removeAudioNode(node) {
        if (!node) return;
        audioSinks = audioSinks.filter(function(n) { return n !== node; });
        audioSources = audioSources.filter(function(n) { return n !== node; });
    }

    // Bind the default audio sink/source so their volume/muted setters work
    PwObjectTracker {
        objects: [controlCenter.audioSink, controlCenter.audioSource]
    }

    // Listen to Pipewire node changes instead of polling every 500ms
    function _syncAudioNodes() {
        try {
            var allNodes = Pipewire.nodes.values;
            var nodes = [];
            for (var i = 0; i < allNodes.length; i++) {
                var n = allNodes[i];
                if (n && (n.type === PwNodeType.AudioSink || n.type === PwNodeType.AudioSource)) {
                    nodes.push(n);
                }
            }
            audioSinks = audioSinks.filter(function(n) { return nodes.indexOf(n) !== -1; });
            audioSources = audioSources.filter(function(n) { return nodes.indexOf(n) !== -1; });
            for (var i = 0; i < nodes.length; i++) {
                if (nodes[i] && nodes[i].ready) controlCenter._addAudioNode(nodes[i]);
            }
        } catch (e) {}
    }

    // Sync audio nodes on a timer (Pipewire doesn't expose a node change signal)
    Timer {
        interval: 2000; repeat: true; running: true
        onTriggered: _syncAudioNodes()
    }

    function setAudioSourceVolume(vol) {
        if (audioSource?.ready && audioSource?.audio) {
            audioSource.audio.muted = false;
            audioSource.audio.volume = Math.max(0, Math.min(1, vol));
        }
    }

    function toggleAudioSourceMute() {
        if (audioSource?.ready && audioSource?.audio) {
            audioSource.audio.muted = !audioSource.audio.muted;
        }
    }

    function setDefaultSink(node) {
        if (node) Pipewire.preferredDefaultAudioSink = node;
    }

    function setDefaultSource(node) {
        if (node) Pipewire.preferredDefaultAudioSource = node;
    }

    function setVolume(vol) {
        if (audioSink?.ready && audioSink?.audio) {
            audioSink.audio.muted = false;
            audioSink.audio.volume = Math.max(0, Math.min(1, vol));
        }
    }

    function toggleMute() {
        if (audioSink?.ready && audioSink?.audio) {
            audioSink.audio.muted = !audioSink.audio.muted;
        }
    }

    function volumeIcon(vol, muted) {
        if (muted || vol <= 0) return "󰝟";
        if (vol < 0.34) return "󰕿";
        if (vol < 0.67) return "󰖀";
        return "󰕾";
    }

    // --- Wi-Fi ---
    property bool wifiEnabled: true
    property string wifiName: "Disconnected"
    property string wifiSecurity: ""
    property var wifiNetworks: []
    property bool wifiScanning: false

    Process {
        id: wifiStatusProc
        command: ["sh", "-c", "e=$(nmcli -t -f WIFI g 2>/dev/null); s=$(nmcli -t -f TYPE,NAME con show --active 2>/dev/null | grep '^802-11-wireless:' | cut -d: -f2); sec=$(nmcli -t -f IN-USE,SECURITY dev wifi 2>/dev/null | grep '^*' | cut -d: -f2); echo \"$e|${s:-}|${sec:-}\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = this.text;
                const parts = out.split("|");
                if (parts.length > 0) controlCenter.wifiEnabled = parts[0].trim() === "enabled";
                const ssid = parts.length > 1 ? parts[1].trim() : "";
                const sec = parts.length > 2 ? parts[2].trim() : "";
                if (ssid) {
                    controlCenter.wifiName = ssid;
                    controlCenter.wifiSecurity = sec;
                } else if (controlCenter.wifiEnabled) {
                    controlCenter.wifiName = "No network";
                    controlCenter.wifiSecurity = "";
                } else {
                    controlCenter.wifiName = "Off";
                    controlCenter.wifiSecurity = "";
                }
            }
        }
    }

    function refreshWifi() { wifiStatusProc.running = true; }

    function toggleWifi() {
        var turningOff = wifiEnabled;
        wifiToggleProc.command = ["nmcli", "radio", "wifi", turningOff ? "off" : "on"];
        wifiToggleProc.running = true;
        wifiEnabled = !wifiEnabled;
        if (turningOff) { wifiName = "Off"; wifiSecurity = ""; }
        wifiRefreshDelay.start();
    }

    Process { id: wifiToggleProc }
    Timer { id: wifiRefreshDelay; interval: 800; onTriggered: refreshWifi() }

    Process {
        id: wifiScanProc
        command: ["sh", "-c", "nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list --rescan yes 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n").filter(l => l.trim().length > 0);
                const seen = {};
                const list = [];
                for (const line of lines) {
                    const fields = line.split(":");
                    if (fields.length < 4) continue;
                    const inUse = fields[0] === "*";
                    const ssid = fields[1];
                    const signal = parseInt(fields[2]) || 0;
                    const security = fields[3];
                    if (!ssid || seen[ssid]) continue;
                    seen[ssid] = true;
                    list.push({ ssid: ssid, signal: signal, security: security, active: inUse });
                }
                list.sort((a, b) => b.signal - a.signal);
                controlCenter.wifiNetworks = list;
                controlCenter.wifiScanning = false;
            }
        }
    }

    function scanWifi() {
        wifiScanning = true;
        wifiScanProc.running = true;
    }

    Timer {
        interval: 8000
        running: controlCenter.isOpen && controlCenter.page === "wifi"
        repeat: true
        triggeredOnStart: true
        onTriggered: controlCenter.scanWifi()
    }

    property string wifiPendingSsid: ""
    property bool wifiNeedsPassword: false
    property string wifiConnectError: ""
    property bool wifiConnecting: false

    function connectToWifi(ssid, security, password) {
        wifiConnecting = true;
        wifiConnectError = "";
        const args = password
            ? ["nmcli", "dev", "wifi", "connect", ssid, "password", password]
            : ["nmcli", "connection", "up", "id", ssid];
        wifiConnectProc.command = args;
        wifiConnectProc.running = true;
    }

    Process {
        id: wifiConnectProc
        stdout: StdioCollector {}
        stderr: StdioCollector {
            onStreamFinished: {
                controlCenter.wifiConnecting = false;
                if (this.text && this.text.toLowerCase().includes("error")) {
                    controlCenter.wifiConnectError = "Couldn't connect — check the password and try again.";
                } else {
                    controlCenter.wifiConnectError = "";
                    controlCenter.wifiPendingSsid = "";
                    controlCenter.refreshWifi();
                    controlCenter.scanWifi();
                }
            }
        }
    }

    function disconnectWifi() {
        wifiDisconnectProc.command = ["sh", "-c", "nmcli -t -f device,type connection show --active | grep wifi | cut -d: -f1 | xargs -r -I{} nmcli con down {}"];
        wifiDisconnectProc.running = true;
        refreshWifiDelay.start();
    }

    Process { id: wifiDisconnectProc }
    Timer { id: refreshWifiDelay; interval: 600; onTriggered: { controlCenter.refreshWifi(); controlCenter.scanWifi(); } }

    function forgetWifi(ssid) {
        forgetProc.command = ["nmcli", "connection", "delete", "id", ssid];
        forgetProc.running = true;
        refreshWifiDelay.start();
    }
    Process { id: forgetProc }

    property string wifiCurrentPassword: ""
    property bool wifiPasswordRevealed: false
    property string wifiQrPath: ""

    Process {
        id: wifiPasswordProc
        stdout: StdioCollector {
            onStreamFinished: { controlCenter.wifiCurrentPassword = this.text.trim(); }
        }
    }

    function loadCurrentWifiPassword() {
        if (!wifiName || wifiName === "No network" || wifiName === "Off") return;
        wifiPasswordProc.command = ["sh", "-c", `nmcli -s -g 802-11-wireless-security.psk connection show '${wifiName.replace(/'/g, "'\\''")}' 2>/dev/null`];
        wifiPasswordProc.running = true;
    }

    Process {
        id: wifiQrProc
        command: ["sh", "-c", "true"]
    }

    Connections {
        target: wifiQrProc
        function onExited() {
            var p = Quickshell.cachePath("wifi-qr.png");
            controlCenter.wifiQrPath = "file://" + p;
        }
    }

    function generateWifiQr() {
        if (!wifiCurrentPassword) { wifiQrPath = ""; return; }
        const security = wifiSecurity && wifiSecurity !== "--" ? "WPA" : "nopass";
        const payload = `WIFI:T:${security};S:${wifiName};P:${wifiCurrentPassword};;`;
        const escaped = payload.replace(/'/g, "'\\''");
        wifiQrProc.command = ["sh", "-c", `qrencode -t PNG -s 6 -o '${Quickshell.cachePath("wifi-qr.png")}' '${escaped}'`];
        wifiQrProc.running = true;
        wifiQrPath = "";
    }

    // --- Bluetooth ---
    readonly property BluetoothAdapter btAdapter: Bluetooth.defaultAdapter
    readonly property var btDevices: btAdapter ? btAdapter.devices.values : []

    function toggleBluetooth() {
        if (btAdapter) btAdapter.enabled = !btAdapter.enabled;
    }

    property bool btScanning: false
    onBtAdapterChanged: { if (!btAdapter) { btScanning = false; } }
    Connections {
        target: controlCenter.btAdapter
        enabled: !!controlCenter.btAdapter
        function onDiscoveringChanged() {
            if (controlCenter.btAdapter && !controlCenter.btAdapter.discovering)
                controlCenter.btScanning = false;
        }
        function onEnabledChanged() {
            if (controlCenter.btAdapter && !controlCenter.btAdapter.enabled)
                controlCenter.btScanning = false;
        }
    }

    function btDeviceSubtitle(dev) {
        if (dev.state === BluetoothDeviceState.Connected) {
            if (dev.batteryAvailable) return "Connected · " + Math.round(dev.battery * 100) + "%";
            return "Connected";
        }
        if (dev.state === BluetoothDeviceState.Connecting) return "Connecting…";
        if (dev.pairing) return "Pairing…";
        if (dev.paired) return "Paired";
        return "Available";
    }

    function toggleBtConnection(dev) {
        if (dev.state === BluetoothDeviceState.Connected) {
            dev.disconnect();
        } else {
            dev.connect();
        }
    }

    function toggleBtScan() {
        if (!btAdapter) return;
        btScanning = !btScanning;
        btAdapter.discovering = btScanning;
    }

    function pairDevice(dev) {
        dev.pair();
    }

    function forgetDevice(dev) {
        if (dev.state === BluetoothDeviceState.Connected)
            dev.disconnect();
        dev.forget();
    }

    // --- Mode Service ---
    property var modeSvc: null

    // --- Night Light ---
    property string nlStatePath: Quickshell.shellPath("scripts/night-light-state.json")
    property bool nlEnabled: false
    property string nlMode: "manual"
    property int nlTemp: 4500
    property int nlDayTemp: 6500
    property int nlNightTemp: 3500

    FileView {
        id: nlStateFile
        path: controlCenter.nlStatePath
        Component.onCompleted: {
            var raw = nlStateFile.text().trim();
            if (!raw) return;
            try {
                var s = JSON.parse(raw);
                controlCenter.nlEnabled = s.enabled || false;
                controlCenter.nlMode = s.mode || "manual";
                controlCenter.nlTemp = s.temperature || 4500;
                controlCenter.nlDayTemp = s.dayTemp || 6500;
                controlCenter.nlNightTemp = s.nightTemp || 3500;
            } catch (e) {}
            controlCenter._applyNightLight();
        }
    }

    function _applyNightLight() {
        if (!nlEnabled) {
            nlProc.command = [Quickshell.shellPath("scripts/nightlight.sh"), "off"];
        } else if (nlMode === "auto") {
            nlProc.command = [
                Quickshell.shellPath("scripts/nightlight.sh"), "auto",
                String(nlDayTemp), String(nlNightTemp)
            ];
        } else {
            nlProc.command = [
                Quickshell.shellPath("scripts/nightlight.sh"), "manual",
                String(nlTemp)
            ];
        }
        nlProc.running = true;
    }

    function _saveNightLight() {
        var s = JSON.stringify({
            enabled: nlEnabled,
            mode: nlMode,
            temperature: nlTemp,
            dayTemp: nlDayTemp,
            nightTemp: nlNightTemp
        });
        nlSaveProc.command = ["sh", "-c",
            "mkdir -p $(dirname \"" + controlCenter.nlStatePath + "\") && " +
            "printf '%s\\n' \"" + s.replace(/\"/g, '\\"') + "\" > \"" + controlCenter.nlStatePath + ".tmp\" && " +
            "mv -f \"" + controlCenter.nlStatePath + ".tmp\" \"" + controlCenter.nlStatePath + "\""
        ];
        nlSaveProc.running = true;
    }

    function toggleNightLight() {
        nlEnabled = !nlEnabled;
        _applyNightLight();
        _saveNightLight();
    }

    function setNightLightTemp(temp) {
        nlTemp = Math.max(1000, Math.min(8000, temp));
        if (nlEnabled && nlMode === "manual") {
            _applyNightLight();
        }
        _saveNightLight();
    }

    function setNightLightAutoTemp(day, night) {
        nlDayTemp = Math.max(1000, Math.min(8000, day));
        nlNightTemp = Math.max(1000, Math.min(8000, night));
        if (nlEnabled && nlMode === "auto") {
            _applyNightLight();
        }
        _saveNightLight();
    }

    Process { id: nlProc }
    Process { id: nlSaveProc }

    // --- Brightness ---
    property real brightness: 0.8
    property string backlightDevice: ""

    Process {
        id: backlightDetectProc
        command: ["sh", "-c", "ls /sys/class/backlight 2>/dev/null | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const name = this.text.trim();
                if (name) controlCenter.backlightDevice = name;
            }
        }
    }

    FileView {
        id: brightnessCurrentFile
        path: controlCenter.backlightDevice
            ? `/sys/class/backlight/${controlCenter.backlightDevice}/brightness`
            : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: controlCenter.syncBrightnessFromSysfs()
        onTextChanged: controlCenter.syncBrightnessFromSysfs()
    }

    FileView {
        id: brightnessMaxFile
        path: controlCenter.backlightDevice
            ? `/sys/class/backlight/${controlCenter.backlightDevice}/max_brightness`
            : ""
    }

    function syncBrightnessFromSysfs() {
        const cur = parseInt(brightnessCurrentFile.text());
        const max = parseInt(brightnessMaxFile.text());
        if (!isNaN(cur) && !isNaN(max) && max > 0) {
            brightness = cur / max;
        }
    }

    function setBrightness(val) {
        brightness = Math.max(0, Math.min(1, val));
        brightnessSetProc.command = ["brightnessctl", "set", Math.round(brightness * 100) + "%"];
        brightnessSetProc.running = true;
    }

    Process { id: brightnessSetProc }

    function brightnessIcon(val) {
        if (val < 0.34) return "󰃞";
        if (val < 0.67) return "󰃟";
        return "󰃠";
    }

    // --- Media player (playerctl) ---
    property QtObject activePlayer: playerctlData

    property string playerArt: ""

    property var playerctlData: QtObject {
        property string identity: "Media Player"
        property string trackTitle: ""
        property string trackArtist: ""
        property string artUrl: ""
        property bool isPlaying: false
        property real position: 0
        property real length: 1

        function previous() {
            playerctlCmd.command = ["playerctl", "--player=playerctld", "previous"]
            playerctlCmd.running = true
        }
        function togglePlaying() {
            playerctlCmd.command = ["playerctl", "--player=playerctld", "play-pause"]
            playerctlCmd.running = true
        }
        function next() {
            playerctlCmd.command = ["playerctl", "--player=playerctld", "next"]
            playerctlCmd.running = true
        }

        function fetch() {
            metaProc.running = false
            metaProc.command = [
                "playerctl", "--player=playerctld", "metadata",
                "--format",
                "{{title}}|~|{{artist}}|~|{{mpris:artUrl}}|~|{{xesam:url}}|~|{{mpris:length}}|~|{{mpris:position}}"
            ]
            metaProc.running = true
        }
    }

    property Process playerctlCmd: Process { command: ["true"]; running: false }

    property Process playerctlStatusProc: Process {
        command: ["playerctl", "--player=playerctld", "status", "--follow"]
        running: true
        stdout: SplitParser {
            onRead: (data) => {
                playerctlData.isPlaying = data.trim() === "Playing"
                playerctlData.fetch()
            }
        }
    }

    property Process metaProc: Process {
        command: ["true"]
        running: false
        stdout: SplitParser {
            onRead: (data) => {
                var parts = data.trim().split("|~|")
                if (parts.length < 6) return
                playerctlData.trackTitle = parts[0] || ""
                playerctlData.trackArtist = parts[1] || ""
                var artUrl = parts[2] || ""
                var pageUrl = parts[3] || ""
                var len = parseFloat(parts[4]) || 0
                var pos = parseFloat(parts[5]) || 0
                playerctlData.length = len > 0 ? len / 1000000 : 1
                playerctlData.position = pos > 0 ? pos / 1000000 : 0
                var newArt = ""
                if (artUrl.startsWith("/"))
                    newArt = "file://" + artUrl
                else if (artUrl)
                    newArt = artUrl
                else if (pageUrl) {
                    var m = pageUrl.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/)([a-zA-Z0-9_-]{11})/)
                    if (m) newArt = "https://img.youtube.com/vi/" + m[1] + "/hqdefault.jpg"
                }
                playerctlData.artUrl = newArt
                if (newArt) playerArt = newArt
            }
        }
    }

    Component.onCompleted: {
        refreshWifi();
        _syncAudioNodes();
        backlightDetectProc.running = true;
        nlStateFile.reload();
    }

    property Timer pctlMetaTimer: Timer {
        interval: 3000; running: true; repeat: true
        onTriggered: playerctlData.fetch()
    }

    // ---- Inline components ----
    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (controlCenter.page !== "main") controlCenter.page = "main";
            else controlCenter.closeRequested();
        }
    }

    // ---- Panel ----
    Rectangle {
        id: panel
        width: 540
        height: Math.min(controlCenter.page === "main" ? mainPageHeightHint : 560, parent.height - 20)

        property real mainPageHeightHint: 290
            + (controlCenter.activePlayer ? 160 : 0)
            + 30
            + 50
            + 30
            + 80
            + 60
            + ((controlCenter.storedNotifications?.length ?? 0) > 0 ? 20: 0)

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 10

        color: Theme.background
        radius: 24
        border.color: Theme.surface
        border.width: 2
        clip: true

        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            // ---- HEADER ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "󰅁"
                    color: Theme.text
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 18 }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (controlCenter.page !== "main") controlCenter.page = "main";
                            else controlCenter.closeRequested();
                        }
                    }
                }

                Text {
                text: controlCenter.page === "wifi" ? "Wi-Fi"
                    : controlCenter.page === "bluetooth" ? "Bluetooth"
                    : controlCenter.page === "audio" ? "Audio"
                    : controlCenter.page === "nightlight" ? "Night Light"
                    : controlCenter.page === "mode" ? "Performance Mode"
                    : "Control Center"
                    color: Theme.text
                    font { family: "Inter"; pixelSize: 15; weight: 700 }
                    Layout.fillWidth: true
                }
            }

            MainPage {
                visible: controlCenter.page === "main"
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12
                page: controlCenter.page
                modeSvc: controlCenter.modeSvc
                wifiEnabled: controlCenter.wifiEnabled
                wifiName: controlCenter.wifiName
                volumeIcon: controlCenter.volumeIcon
                audioVolume: controlCenter.audioVolume
                audioMuted: controlCenter.audioMuted
                audioSink: controlCenter.audioSink
                btAdapter: controlCenter.btAdapter
                nlEnabled: controlCenter.nlEnabled
                doNotDisturb: controlCenter.doNotDisturb
                brightnessIcon: controlCenter.brightnessIcon
                brightness: controlCenter.brightness
                activePlayer: controlCenter.activePlayer
                playerArt: controlCenter.playerArt
                storedNotifications: controlCenter.storedNotifications
                onNavigateTo: (p) => controlCenter.page = p
                onToggleWifi: controlCenter.toggleWifi()
                onScanWifi: controlCenter.scanWifi()
                onLoadCurrentWifiPassword: controlCenter.loadCurrentWifiPassword()
                onToggleMute: controlCenter.toggleMute()
                onToggleBluetooth: controlCenter.toggleBluetooth()
                onToggleNightLight: controlCenter.toggleNightLight()
                onToggleDnd: { controlCenter.doNotDisturb = !controlCenter.doNotDisturb; controlCenter.dndToggled(controlCenter.doNotDisturb); }
                onSetVolume: (v) => controlCenter.setVolume(v)
                onSetBrightness: (v) => controlCenter.setBrightness(v)
                onDismissNotif: (n) => controlCenter.dismissNotif(n)
                onClearNotifs: controlCenter.clearNotifs()
            }

            WifiPage {
                visible: controlCenter.page === "wifi"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                wifiEnabled: controlCenter.wifiEnabled
                wifiName: controlCenter.wifiName
                wifiSecurity: controlCenter.wifiSecurity
                wifiNetworks: controlCenter.wifiNetworks
                wifiScanning: controlCenter.wifiScanning
                wifiConnecting: controlCenter.wifiConnecting
                wifiQrPath: controlCenter.wifiQrPath
                onToggleWifi: controlCenter.toggleWifi()
                onScanWifi: controlCenter.scanWifi()
                onConnectToWifi: (ssid, security, pw) => controlCenter.connectToWifi(ssid, security, pw)
                onLoadCurrentWifiPassword: controlCenter.loadCurrentWifiPassword()
                onDisconnectWifi: controlCenter.disconnectWifi()
                onGenerateWifiQr: controlCenter.generateWifiQr()
                onRequestPassword: (ssid) => { controlCenter.wifiPendingSsid = ssid; controlCenter.wifiNeedsPassword = true; }
                onBackRequested: controlCenter.page = "main"
                onShowQrCode: (path) => controlCenter.showQrCode(path)
            }

            // ---- BLUETOOTH PAGE ----
            BluetoothPage {
              visible: controlCenter.page === "bluetooth"
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              btAdapter: controlCenter.btAdapter
              btDevices: controlCenter.btDevices
              btScanning: controlCenter.btScanning
              btDeviceSubtitle: controlCenter.btDeviceSubtitle
              onToggleBluetooth: controlCenter.toggleBluetooth()
              onToggleBtScan: controlCenter.toggleBtScan()
              onForgetDevice: (device) => controlCenter.forgetDevice(device)
              onPairDevice: (device) => controlCenter.pairDevice(device)
              onToggleBtConnection: (device) => controlCenter.toggleBtConnection(device)
              onBackRequested: controlCenter.page = "main"
            }

            // ---- AUDIO PAGE ----
            AudioPage {
              visible: controlCenter.page === "audio"
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              audioSinks: controlCenter.audioSinks
              audioSink: controlCenter.audioSink
              audioSources: controlCenter.audioSources
              audioSource: controlCenter.audioSource
              audioVolume: controlCenter.audioVolume
              audioMuted: controlCenter.audioMuted
              audioSourceVolume: controlCenter.audioSourceVolume
              audioSourceMuted: controlCenter.audioSourceMuted
              volumeIcon: controlCenter.volumeIcon
              onBackRequested: controlCenter.page = "main"
              onSetVolume: (v) => controlCenter.setVolume(v)
              onToggleMute: controlCenter.toggleMute()
              onSetAudioSourceVolume: (v) => controlCenter.setAudioSourceVolume(v)
              onToggleAudioSourceMute: controlCenter.toggleAudioSourceMute()
              onSetDefaultSink: (n) => controlCenter.setDefaultSink(n)
              onSetDefaultSource: (n) => controlCenter.setDefaultSource(n)
            }

            // ---- NIGHT LIGHT PAGE ----
            NightLightPage {
              visible: controlCenter.page === "nightlight"
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              nlEnabled: controlCenter.nlEnabled
              nlMode: controlCenter.nlMode
              nlTemp: controlCenter.nlTemp
              nlDayTemp: controlCenter.nlDayTemp
              nlNightTemp: controlCenter.nlNightTemp
              onBackRequested: controlCenter.page = "main"
              onToggleNightLight: controlCenter.toggleNightLight()
              onSetNightLightTemp: (t) => controlCenter.setNightLightTemp(t)
              onSetNightLightMode: (mode) => { controlCenter.nlMode = mode; if (controlCenter.nlEnabled) controlCenter._applyNightLight(); controlCenter._saveNightLight(); }
              onSetNightLightAutoTemp: (d, n) => controlCenter.setNightLightAutoTemp(d, n)
              onApplyNightLight: controlCenter._applyNightLight()
              onSaveNightLight: controlCenter._saveNightLight()
            }

            // ---- MODE PAGE ----
            ModePage {
              visible: controlCenter.page === "mode"
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              currentMode: controlCenter.modeSvc ? controlCenter.modeSvc.currentMode : "balanced"
              cpuTemp: controlCenter.modeSvc ? controlCenter.modeSvc.cpuTemp : 0
              onSetMode: (m) => { if (controlCenter.modeSvc) controlCenter.modeSvc.setMode(m); }
              onBackRequested: controlCenter.page = "main"
            }
        }
    }

    WifiPasswordDialog {
      anchors.fill: parent
      visible: controlCenter.wifiNeedsPassword
      pendingSsid: controlCenter.wifiPendingSsid
      connectError: controlCenter.wifiConnectError
      connecting: controlCenter.wifiConnecting
      onDismiss: controlCenter.wifiNeedsPassword = false
      onConnectRequested: (ssid, pw) => controlCenter.connectToWifi(ssid, "secured", pw)
    }
}
