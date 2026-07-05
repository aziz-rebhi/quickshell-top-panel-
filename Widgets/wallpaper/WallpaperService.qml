import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
  id: svc

  property var wallpapers: []

  signal wallpaperApplied(string path)

  property Process scanProc: Process {
    command: ["sh", "-c", "ls ~/Pictures/Wallpapers/*.{jpg,jpeg,png,bmp,webp,gif} 2>/dev/null | head -200"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        var list = this.text.trim().split("\n").filter(function(p) { return p.length > 0 })
        list.sort()
        svc.wallpapers = list
      }
    }
  }

  property Process _applyProc: Process {
    stdout: StdioCollector {
      onStreamFinished: {
        var out = this.text.trim()
        if (out) console.log("wallpaper.sh stdout:", out)
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        var err = this.text.trim()
        if (err) console.error("wallpaper.sh stderr:", err)
      }
    }
  }

  function rescan() {
    scanProc.running = true
  }

  function applyWallpaper(path) {
    console.log("applying wallpaper:", path)
    _applyProc.command = [Quickshell.shellPath("scripts/wallpaper.sh"), path]
    _applyProc.running = true
  }
}
