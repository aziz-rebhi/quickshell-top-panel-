import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.core

/*!
  AppLauncher — Dynamic Island app launcher UI.

  Bind service from parent:
    AppLauncher {
      service: appLauncherService
      active: showAppLauncher
      onRequestClose: showAppLauncher = false
    }

  Features:
  - Fuzzy search with ranking (name, keywords, categories, id)
  - Pins + recents when query is empty
  - Category chips
  - List / grid toggle
  - Keyboard: type to search, Up/Down or Ctrl+J/K, Enter to launch, Esc to close
  - Right-click (or pin button) to pin/unpin
  - Lazy icons via service
*/
Item {
    id: root

    // ── external API (ClockWidget binds these) ──────────────────────────────
    property var service: null   // AppLauncherService instance
    property alias appService: root.service
    property bool active: false
    property bool hovered: false
    signal requestClose()
    signal closeRequested()
    signal launched()

    readonly property var svc: service
    readonly property bool svcScanning: service ? service.scanning : false
    readonly property string svcScanError: service ? (service.scanError || "") : ""

    // ── local state ─────────────────────────────────────────────────────────
    property string query: ""
    property int selectedIndex: 0
    property bool gridMode: false
    property string category: "All"   // "All" or FreeDesktop category name
    property var results: []

    readonly property int maxVisibleList: 8
    readonly property int gridColumns: 5

    onActiveChanged: {
        if (active) {
            query = ""
            category = "All"
            selectedIndex = 0
            rebuild()
            Qt.callLater(() => searchField.forceActiveFocus())
        }
    }

    Connections {
        target: root.service
        function onCatalogChanged() { if (root.active) root.rebuild() }
        function onPinsChanged() { if (root.active) root.rebuild() }
    }

    function rebuild() {
        if (!root.svc) {
            results = []
            return
        }
        if (category !== "All" && !query.trim()) {
            results = root.svc.filterByCategory(category)
        } else {
            results = root.svc.search(query)
        }
        if (selectedIndex >= results.length)
            selectedIndex = Math.max(0, results.length - 1)
        if (results.length === 0)
            selectedIndex = 0
    }

    function moveSelection(delta) {
        if (!results.length)
            return
        let next = selectedIndex + delta
        if (next < 0)
            next = results.length - 1
        if (next >= results.length)
            next = 0
        selectedIndex = next
        listView.positionViewAtIndex(selectedIndex, ListView.Contain)
    }

    function activateSelected() {
        if (!results.length || !root.svc)
            return
        const app = results[selectedIndex]
        if (!app || !app.id)
            return
        root.svc.launch(app.id)
        root.launched()
        root.close()
    }

    function close() {
        root.requestClose()
        root.closeRequested()
    }

    function pinSelected() {
        if (!results.length || !root.svc)
            return
        const app = results[selectedIndex]
        if (app && app.id)
            root.svc.togglePin(app.id)
    }

    // ── chrome ──────────────────────────────────────────────────────────────
    Rectangle {
        id: panel
        anchors.fill: parent
        color: Theme.background
        radius: 28
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            // Search row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "󰍉"  // search nf icon
                    font.family: Fonts.mono
                    font.pixelSize: 16
                    color: Theme.subtext
                }

                TextInput {
                    id: searchField
                    Layout.fillWidth: true
                    color: Theme.text
                    font.family: Fonts.main
                    font.pixelSize: 14
                    selectByMouse: true
                    clip: true
                    text: root.query
                    onTextChanged: {
                        if (text !== root.query) {
                            root.query = text
                            root.selectedIndex = 0
                            root.rebuild()
                        }
                    }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: root.svcScanning ? "Scanning apps…" : "Search apps…"
                        color: Theme.subtext
                        font: searchField.font
                        visible: !searchField.text && !searchField.activeFocus
                        opacity: 0.6
                    }

                    Keys.onPressed: function (event) {
                        if (event.key === Qt.Key_Down || (event.key === Qt.Key_J && event.modifiers & Qt.ControlModifier)) {
                            root.moveSelection(1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_K && event.modifiers & Qt.ControlModifier)) {
                            root.moveSelection(-1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.activateSelected()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            root.close()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Tab) {
                            root.gridMode = !root.gridMode
                            event.accepted = true
                        } else if (event.key === Qt.Key_P && event.modifiers & Qt.ControlModifier) {
                            root.pinSelected()
                            event.accepted = true
                        }
                    }
                }

                // Grid / list toggle
                Rectangle {
                    width: 28
                    height: 28
                    radius: 8
                    color: gridBtn.containsMouse ? Theme.surfaceHover || Theme.surfaceBright : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: root.gridMode ? "󰯋" : "󰡫"  // list vs grid
                        font.family: Fonts.mono
                        font.pixelSize: 14
                        color: Theme.subtext
                    }
                    MouseArea {
                        id: gridBtn
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.gridMode = !root.gridMode
                    }
                }

                // Rescan
                Rectangle {
                    width: 28
                    height: 28
                    radius: 8
                    color: rescanBtn.containsMouse ? Theme.surfaceHover || Theme.surfaceBright : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "󰑓"
                        font.family: Fonts.mono
                        font.pixelSize: 14
                        color: root.svcScanning ? Theme.accent || Theme.primary : Theme.subtext
                        RotationAnimator on rotation {
                            running: root.svcScanning
                            from: 0
                            to: 360
                            duration: 900
                            loops: Animation.Infinite
                        }
                    }
                    MouseArea {
                        id: rescanBtn
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.svc) root.svc.rescan()
                    }
                }
            }

            // Category chips (hidden while searching)
            Flickable {
                id: chipFlick
                Layout.fillWidth: true
                Layout.preferredHeight: root.query.trim() ? 0 : 28
                visible: height > 0
                contentWidth: chipRow.width
                clip: true
                interactive: contentWidth > width
                flickableDirection: Flickable.HorizontalFlick

                Behavior on Layout.preferredHeight {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }

                Row {
                    id: chipRow
                    spacing: 6
                    Repeater {
                        model: {
                            const main = ["All", "Network", "AudioVideo", "Development", "Office",
                                          "Graphics", "Game", "System", "Utility", "Settings"]
                            const available = { "All": true }
                            if (root.svc) {
                                const cats = root.svc.allCategories()
                                for (let i = 0; i < cats.length; i++)
                                    available[cats[i]] = true
                            }
                            return main.filter(c => available[c] || c === "All")
                        }
                        delegate: Rectangle {
                            required property string modelData
                            height: 26
                            width: chipLabel.implicitWidth + 16
                            radius: 13
                            color: root.category === modelData ? Theme.accent || Theme.primary : Theme.surfaceHover || Theme.surfaceBright
                            opacity: chipMa.containsMouse || root.category === modelData ? 1 : 0.85

                            Text {
                                id: chipLabel
                                anchors.centerIn: parent
                                text: {
                                    const map = {
                                        "All": "All",
                                        "Network": "Internet",
                                        "AudioVideo": "Media",
                                        "Development": "Dev",
                                        "Office": "Office",
                                        "Graphics": "Graphics",
                                        "Game": "Games",
                                        "System": "System",
                                        "Utility": "Utils",
                                        "Settings": "Settings"
                                    }
                                    return map[modelData] || modelData
                                }
                                font.family: Fonts.main
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                color: root.category === modelData ? (Theme.primaryFg || Theme.background) : Theme.text
                            }
                            MouseArea {
                                id: chipMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.category = modelData
                                    root.selectedIndex = 0
                                    root.rebuild()
                                }
                            }
                        }
                    }
                }
            }

            // Results
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Empty / loading / error
                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    visible: !root.results.length
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.svcScanning ? "󰔟" : (root.svcScanError ? "󰅙" : "󰍉")
                        font.family: Fonts.mono
                        font.pixelSize: 28
                        color: Theme.subtext
                        opacity: 0.5
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: {
                            if (root.svcScanning)
                                return "Scanning applications…"
                            if (root.svcScanError)
                                return "Scan failed — click rescan"
                            if (root.query.trim())
                                return "No matches for \"" + root.query + "\""
                            return "No applications found"
                        }
                        font.family: Fonts.main
                        font.pixelSize: 12
                        color: Theme.subtext
                    }
                }

                // List mode
                ListView {
                    id: listView
                    anchors.fill: parent
                    visible: !root.gridMode && root.results.length > 0
                    clip: true
                    model: root.results
                    currentIndex: root.selectedIndex
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        width: 4
                    }

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        width: listView.width
                        height: 40
                        radius: 10
                        color: {
                            if (index === root.selectedIndex)
                                return Theme.accent || Theme.primary
                            if (rowMa.containsMouse)
                                return Theme.surfaceHover || Theme.surfaceBright
                            return "transparent"
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 10

                            // Icon
                            Item {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                Image {
                                    id: appIcon
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    smooth: true
                                    source: {
                                        const name = modelData.icon || ""
                                        if (name.startsWith("/"))
                                            return "file://" + name
                                        const resolved = root.svc.iconPath(name)
                                        return resolved ? ("file://" + resolved) : ""
                                    }
                                    visible: status === Image.Ready
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: appIcon.status !== Image.Ready
                                    text: "󰘔"
                                    font.family: Fonts.mono
                                    font.pixelSize: 18
                                    color: index === root.selectedIndex ? (Theme.primaryFg || Theme.background) : Theme.subtext
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name || modelData.id
                                    elide: Text.ElideRight
                                    font.family: Fonts.main
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    color: index === root.selectedIndex ? (Theme.primaryFg || Theme.background) : Theme.text
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: !!(modelData.genericName || modelData.comment || modelData.flatpak)
                                    text: {
                                        const bits = []
                                        if (modelData.flatpak)
                                            bits.push("Flatpak")
                                        if (modelData.genericName)
                                            bits.push(modelData.genericName)
                                        else if (modelData.comment)
                                            bits.push(modelData.comment)
                                        return bits.join(" · ")
                                    }
                                    elide: Text.ElideRight
                                    font.family: Fonts.main
                                    font.pixelSize: 10
                                    color: index === root.selectedIndex ? (Theme.primaryFg || Theme.background) : Theme.subtext
                                    opacity: 0.85
                                }
                            }

                            // Pin indicator / button
                            Text {
                                text: root.svc.isPinned(modelData.id) ? "󰐃" : "󰐄"
                                font.family: Fonts.mono
                                font.pixelSize: 14
                                color: index === root.selectedIndex ? (Theme.primaryFg || Theme.background) : Theme.subtext
                                opacity: root.svc.isPinned(modelData.id) || pinMa.containsMouse ? 1 : 0.35
                                MouseArea {
                                    id: pinMa
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.svc.togglePin(modelData.id)
                                }
                            }
                        }

                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onPositionChanged: root.selectedIndex = index
                            onClicked: function (mouse) {
                                root.selectedIndex = index
                                if (mouse.button === Qt.RightButton)
                                    root.svc.togglePin(modelData.id)
                                else {
                                    root.activateSelected()
                                }
                            }
                        }
                    }
                }

                // Grid mode
                GridView {
                    id: gridView
                    anchors.fill: parent
                    visible: root.gridMode && root.results.length > 0
                    clip: true
                    model: root.results
                    cellWidth: Math.floor(width / root.gridColumns)
                    cellHeight: 78
                    currentIndex: root.selectedIndex
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        id: cell
                        required property var modelData
                        required property int index
                        width: gridView.cellWidth - 4
                        height: gridView.cellHeight - 4
                        radius: 12
                        color: {
                            if (index === root.selectedIndex)
                                return Theme.accent || Theme.primary
                            if (cellMa.containsMouse)
                                return Theme.surfaceHover || Theme.surfaceBright
                            return "transparent"
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            width: parent.width - 8

                            Item {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 36
                                height: 36
                                Image {
                                    id: gIcon
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    source: {
                                        const name = modelData.icon || ""
                                        if (name.startsWith("/"))
                                            return "file://" + name
                                        const resolved = root.svc.iconPath(name)
                                        return resolved ? ("file://" + resolved) : ""
                                    }
                                    visible: status === Image.Ready
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: gIcon.status !== Image.Ready
                                    text: "󰘔"
                                    font.family: Fonts.mono
                                    font.pixelSize: 22
                                    color: index === root.selectedIndex ? (Theme.primaryFg || Theme.background) : Theme.subtext
                                }
                            }
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.name || modelData.id
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.Wrap
                                font.family: Fonts.main
                                font.pixelSize: 10
                                color: index === root.selectedIndex ? (Theme.primaryFg || Theme.background) : Theme.text
                            }
                        }

                        // Pin badge
                        Text {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 4
                            visible: root.svc.isPinned(modelData.id)
                            text: "󰐃"
                            font.family: Fonts.mono
                            font.pixelSize: 11
                            color: index === root.selectedIndex ? (Theme.primaryFg || Theme.background) : Theme.accent || Theme.primary
                        }

                        MouseArea {
                            id: cellMa
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onPositionChanged: root.selectedIndex = index
                            onClicked: function (mouse) {
                                root.selectedIndex = index
                                if (mouse.button === Qt.RightButton)
                                    root.svc.togglePin(modelData.id)
                                else
                                    root.activateSelected()
                            }
                        }
                    }
                }
            }

            // Footer hint
            Text {
                Layout.fillWidth: true
                text: "↵ open   ⌃J/K move   ⌃P pin   Tab grid   Esc close"
                font.family: Fonts.mono
                font.pixelSize: 10
                color: Theme.subtext
                opacity: 0.55
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    // Keep selection visible when results change
    onResultsChanged: {
        if (selectedIndex >= results.length)
            selectedIndex = Math.max(0, results.length - 1)
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onContainsMouseChanged: root.hovered = containsMouse
    }
}
