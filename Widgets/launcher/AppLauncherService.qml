import QtQuick
import Quickshell
import Quickshell.Io

/*!
  AppLauncherService — scan, search, rank, pin, history, launch.

  Instantiate once in shell.qml and pass into AppLauncher / ClockWidget:
    AppLauncherService { id: appLauncherService }

  Uses scripts/desktop-apps.py for reliable .desktop parsing / launch.
  State files:
    ~/.cache/quickshell/launcher-history.json   { "id": { "count": N, "last": epoch } }
    ~/.config/quickshell/launcher-pins.json     [ "id", ... ]
*/
Item {
    id: root

    // ── public API ──────────────────────────────────────────────────────────
    property bool ready: false
    property bool scanning: false
    property string scanError: ""

    /** Full catalog after scan (array of JS objects). */
    property var apps: []

    /** Pins (desktop ids), highest priority first. */
    property var pins: []

    /** History map id → { count, last }. */
    property var history: ({})

    readonly property string scriptPath: {
        var home = Quickshell.env("HOME") || ""
        return home + "/.config/quickshell/scripts/desktop-apps.py"
    }
    readonly property string historyPath: {
        var home = Quickshell.env("HOME") || ""
        return home + "/.cache/quickshell/launcher-history.json"
    }
    readonly property string pinsPath: {
        var home = Quickshell.env("HOME") || ""
        return home + "/.config/quickshell/launcher-pins.json"
    }

    signal catalogChanged()

    Component.onCompleted: {
        loadHistory()
        loadPins()
        rescan()
    }

    // ── scan ────────────────────────────────────────────────────────────────
    function rescan() {
        if (scanning)
            return
        scanning = true
        scanError = ""
        scanProc.running = false
        scanProc.running = true
    }

    Process {
        id: scanProc
        command: ["python3", root.scriptPath, "scan"]
        stdout: StdioCollector {
            id: scanOut
            waitForEnd: true
            onStreamFinished: {
                root.scanning = false
                try {
                    const text = (scanOut.text || "").trim()
                    if (!text) {
                        root.scanError = "empty scan result"
                        root.apps = []
                        root.catalogChanged()
                        return
                    }
                    const data = JSON.parse(text)
                    if (!Array.isArray(data)) {
                        root.scanError = "invalid JSON"
                        root.apps = []
                    } else {
                        root.apps = data
                        root.scanError = ""
                    }
                    root.ready = true
                    root.catalogChanged()
                } catch (e) {
                    root.scanError = String(e)
                    root.apps = []
                    root.catalogChanged()
                }
            }
        }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (this.text && this.text.trim())
                    console.warn("[AppLauncherService] scan stderr:", this.text.trim())
            }
        }
        onExited: function (code) {
            if (code !== 0 && root.scanning) {
                root.scanning = false
                root.scanError = "scan exited " + code
                root.catalogChanged()
            }
        }
    }

    // ── search / rank ───────────────────────────────────────────────────────
    /*!
      Returns ranked list of app objects for query.
      Empty query → pins first, then recents, then A–Z.
      Non-empty → scored matches, pins boosted.
    */
    function search(query) {
        const q = (query || "").trim().casefold ? (query || "").trim().toLowerCase()
                                                 : (query || "").trim().toLowerCase()
        const list = root.apps || []
        if (!list.length)
            return []

        if (!q) {
            // Default view: pins → recent (by last) → rest alpha
            const pinSet = {}
            for (let i = 0; i < root.pins.length; i++)
                pinSet[root.pins[i]] = true

            const pinned = []
            const rest = []
            for (let i = 0; i < list.length; i++) {
                const a = list[i]
                if (pinSet[a.id])
                    pinned.push(Object.assign({ _pin: true, _score: 1e9 }, a))
                else
                    rest.push(a)
            }
            // Keep pin order
            pinned.sort((a, b) => root.pins.indexOf(a.id) - root.pins.indexOf(b.id))

            rest.sort((a, b) => {
                const ha = root.history[a.id]
                const hb = root.history[b.id]
                const la = ha ? (ha.last || 0) : 0
                const lb = hb ? (hb.last || 0) : 0
                if (la !== lb)
                    return lb - la
                return String(a.name).localeCompare(String(b.name), undefined, { sensitivity: "base" })
            })
            return pinned.concat(rest)
        }

        // Scored search
        const results = []
        for (let i = 0; i < list.length; i++) {
            const a = list[i]
            const score = scoreApp(a, q)
            if (score <= 0)
                continue
            const boost = root.pins.indexOf(a.id) >= 0 ? 500 : 0
            const hist = root.history[a.id]
            const freq = hist ? Math.min(50, (hist.count || 0) * 2) : 0
            results.push(Object.assign({
                _score: score + boost + freq,
                _pin: boost > 0
            }, a))
        }
        results.sort((a, b) => {
            if (b._score !== a._score)
                return b._score - a._score
            return String(a.name).localeCompare(String(b.name), undefined, { sensitivity: "base" })
        })
        return results
    }

    function scoreApp(a, q) {
        const name = String(a.name || "").toLowerCase()
        const generic = String(a.genericName || "").toLowerCase()
        const id = String(a.id || "").toLowerCase()
        const comment = String(a.comment || "").toLowerCase()
        const keywords = (a.keywords || []).map(k => String(k).toLowerCase())
        const cats = (a.categories || []).map(c => String(c).toLowerCase())

        // Exact / prefix on name
        if (name === q)
            return 1000
        if (name.startsWith(q))
            return 800
        // Word-prefix (each word)
        const words = name.split(/\s+/)
        for (let i = 0; i < words.length; i++) {
            if (words[i].startsWith(q))
                return 700
        }
        // Substring name
        if (name.indexOf(q) >= 0)
            return 500
        // Fuzzy subsequence
        if (subsequence(name, q))
            return 350
        // Keywords
        for (let i = 0; i < keywords.length; i++) {
            if (keywords[i] === q)
                return 450
            if (keywords[i].startsWith(q) || keywords[i].indexOf(q) >= 0)
                return 300
        }
        // Generic name / id / categories / comment
        if (generic.startsWith(q) || generic.indexOf(q) >= 0)
            return 280
        if (id.startsWith(q) || id.indexOf(q) >= 0)
            return 250
        for (let i = 0; i < cats.length; i++) {
            if (cats[i].toLowerCase().indexOf(q) >= 0)
                return 200
        }
        if (comment.indexOf(q) >= 0)
            return 120
        return 0
    }

    function subsequence(text, q) {
        let ti = 0
        for (let qi = 0; qi < q.length; qi++) {
            const ch = q[qi]
            let found = false
            while (ti < text.length) {
                if (text[ti++] === ch) {
                    found = true
                    break
                }
            }
            if (!found)
                return false
        }
        return true
    }

    // ── categories helper ───────────────────────────────────────────────────
    /** Unique top-level categories present in catalog. */
    function allCategories() {
        const set = {}
        const list = root.apps || []
        for (let i = 0; i < list.length; i++) {
            const cats = list[i].categories || []
            for (let j = 0; j < cats.length; j++) {
                const c = String(cats[j]).trim()
                if (!c || c === "Application")
                    continue
                // Prefer main FreeDesktop categories
                set[c] = true
            }
        }
        const keys = Object.keys(set)
        keys.sort()
        return keys
    }

    function filterByCategory(category) {
        if (!category || category === "All")
            return search("")
        const q = String(category).toLowerCase()
        const list = root.apps || []
        const out = []
        for (let i = 0; i < list.length; i++) {
            const a = list[i]
            const cats = (a.categories || []).map(c => String(c).toLowerCase())
            if (cats.indexOf(q) >= 0)
                out.push(Object.assign({ _pin: root.pins.indexOf(a.id) >= 0 }, a))
        }
        out.sort((a, b) => String(a.name).localeCompare(String(b.name), undefined, { sensitivity: "base" }))
        return out
    }

    // ── launch ──────────────────────────────────────────────────────────────
    function launch(desktopId) {
        if (!desktopId)
            return
        recordLaunch(desktopId)
        launchProc.command = ["python3", root.scriptPath, "launch", desktopId]
        launchProc.running = false
        launchProc.running = true
    }

    Process {
        id: launchProc
        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (this.text && this.text.trim())
                    console.warn("[AppLauncherService] launch:", this.text.trim())
            }
        }
    }

    // ── history ─────────────────────────────────────────────────────────────
    function recordLaunch(desktopId) {
        const h = Object.assign({}, root.history)
        const prev = h[desktopId] || { count: 0, last: 0 }
        h[desktopId] = {
            count: (prev.count || 0) + 1,
            last: Math.floor(Date.now() / 1000)
        }
        root.history = h
        saveHistory()
    }

    function loadHistory() {
        histLoader.path = root.historyPath
        // FileView reload below
        histLoader.reload()
    }

    function saveHistory() {
        try {
            const text = JSON.stringify(root.history)
            const b64 = Qt.btoa(text)
            histWriter.command = [
                "sh", "-c",
                "mkdir -p \"$HOME/.cache/quickshell\" && echo '" + b64 + "' | base64 -d > \"$HOME/.cache/quickshell/launcher-history.json\""
            ]
            histWriter.running = false
            histWriter.running = true
        } catch (e) {
            console.warn("[AppLauncherService] saveHistory:", e)
        }
    }

    FileView {
        id: histLoader
        path: root.historyPath
        watchChanges: false
        onLoaded: {
            try {
                const t = (text || "").trim()
                if (t)
                    root.history = JSON.parse(t)
            } catch (e) {
                console.warn("[AppLauncherService] loadHistory:", e)
                root.history = ({})
            }
        }
        onLoadFailed: root.history = ({})
    }

    Process {
        id: histWriter
        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
    }

    // ── pins ────────────────────────────────────────────────────────────────
    function isPinned(desktopId) {
        return root.pins.indexOf(desktopId) >= 0
    }

    function togglePin(desktopId) {
        if (!desktopId)
            return
        const arr = root.pins.slice()
        const idx = arr.indexOf(desktopId)
        if (idx >= 0)
            arr.splice(idx, 1)
        else
            arr.push(desktopId)
        root.pins = arr
        savePins()
    }

    function loadPins() {
        pinsLoader.path = root.pinsPath
        pinsLoader.reload()
    }

    function savePins() {
        try {
            const text = JSON.stringify(root.pins)
            const b64 = Qt.btoa(text)
            pinsWriter.command = [
                "sh", "-c",
                "mkdir -p \"$HOME/.config/quickshell\" && echo '" + b64 + "' | base64 -d > \"$HOME/.config/quickshell/launcher-pins.json\""
            ]
            pinsWriter.running = false
            pinsWriter.running = true
        } catch (e) {
            console.warn("[AppLauncherService] savePins:", e)
        }
    }

    FileView {
        id: pinsLoader
        path: root.pinsPath
        watchChanges: false
        onLoaded: {
            try {
                const t = (text || "").trim()
                if (t) {
                    const data = JSON.parse(t)
                    root.pins = Array.isArray(data) ? data : []
                }
            } catch (e) {
                root.pins = []
            }
        }
        onLoadFailed: {
            root.pins = []
        }
    }

    Process {
        id: pinsWriter
        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
    }

    // ── icon cache (lazy) ───────────────────────────────────────────────────
    property var iconCache: ({})

    function iconPath(iconName) {
        if (!iconName)
            return ""
        if (iconName.startsWith("/"))
            return iconName
        const cached = root.iconCache[iconName]
        if (cached !== undefined)
            return cached || ""
        Qt.callLater(function() {
            iconResolver.resolve(iconName)
        })
        return ""
    }

    QtObject {
        id: iconResolver
        property var queue: []
        property bool busy: false

        function resolve(name) {
            if (!name || root.iconCache[name] !== undefined)
                return
            // mark pending so we don't queue twice
            root.iconCache[name] = ""
            root.iconCacheChanged()
            queue.push(name)
            pump()
        }

        function pump() {
            if (busy || !queue.length)
                return
            busy = true
            const name = queue.shift()
            iconProc.command = ["python3", root.scriptPath, "resolve-icon", name]
            iconProc._name = name
            iconProc.running = false
            iconProc.running = true
        }
    }

    Process {
        id: iconProc
        property string _name: ""
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const path = (this.text || "").trim()
                const name = iconProc._name
                if (name) {
                    const cache = Object.assign({}, root.iconCache)
                    cache[name] = path
                    root.iconCache = cache
                }
                iconResolver.busy = false
                iconResolver.pump()
            }
        }
        stderr: StdioCollector { waitForEnd: true }
        onExited: function (code) {
            if (code !== 0)
                console.warn("[AppLauncherService] icon resolver exited:", code)
        }
    }
}
