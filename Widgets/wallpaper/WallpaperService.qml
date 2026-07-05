import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
  id: svc

  property var wallpapers: []

  property var candidateColors: []
  property bool pickingColor: false
  property bool colorPickLoading: false

  signal wallpaperApplied(string path)
  signal colorsReady(var colors)
  signal colorApplied(string sourceColor)

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

  property Process _setWallpaperProc: Process {
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

  property Process _extractColorsProc: Process {
    stdout: StdioCollector {
      onStreamFinished: {
        svc.colorPickLoading = false
        var out = this.text.trim()
        if (out.length > 0) {
          try {
            var parsed = JSON.parse(out)
            if (Array.isArray(parsed) && parsed.length > 0) {
              svc.candidateColors = parsed
              svc.pickingColor = true
              svc.colorsReady(parsed)
              return
            }
          } catch (e) {
            console.error("matugen-pick parse error:", e)
          }
        }
        // Fallback: apply default
        svc.candidateColors = []
        svc.pickingColor = false
        svc.applyDefaultColor()
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        var err = this.text.trim()
        if (err) console.error("matugen-pick.sh stderr:", err)
      }
    }
  }

  property Process _applyColorProc: Process {
    stdout: StdioCollector {
      onStreamFinished: {
        console.log("matugen stdout:", this.text.trim())
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        var err = this.text.trim()
        if (err) console.error("matugen stderr:", err)
      }
    }
  }

  function rescan() {
    scanProc.running = true
  }

  function setWallpaperOnly(path) {
    console.log("setting wallpaper:", path)
    _setWallpaperProc.command = [Quickshell.shellPath("scripts/wallpaper.sh"), "--set-only", path]
    _setWallpaperProc.running = true
  }

  function extractColors(path) {
    console.log("extracting colors:", path)
    svc.colorPickLoading = true
    _extractColorsProc.command = [Quickshell.shellPath("scripts/matugen-pick.sh"), path]
    _extractColorsProc.running = true
  }

  function applyWallpaper(path) {
    console.log("applying wallpaper with color pick:", path)
    svc.setWallpaperOnly(path)
    svc.extractColors(path)
    svc.wallpaperApplied(path)
  }

  function applySourceColor(hex) {
    console.log("applying source color:", hex)
    svc.candidateColors = []
    svc.pickingColor = false
    svc.colorApplied(hex)
    _applyColorProc.command = [
      "matugen", "color", "hex", hex,
      "-m", "dark",
      "--type", "scheme-fidelity",
      "-c", Quickshell.shellPath("../matugen/config.toml")
    ]
    _applyColorProc.running = true
  }

  function applyDefaultColor() {
    if (svc.candidateColors.length > 0) {
      svc.applySourceColor(svc.candidateColors[0])
    } else {
      svc.pickingColor = false
    }
  }

  function cancelPick() {
    svc.pickingColor = false
    svc.candidateColors = []
  }
}
