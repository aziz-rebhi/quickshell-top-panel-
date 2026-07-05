import Quickshell
import Quickshell.Io
import QtQuick

QtObject {
  id: playerctl

  property bool playing: false
  property string title: "No Media"
  property string artist: "Unknown Artist"
  property string art: ""
  property real position: 0
  property real length: 1

  function previous() {
    cmdProc.command = ["playerctl", "--player=playerctld", "previous"]
    cmdProc.running = true
  }

  function togglePlaying() {
    cmdProc.command = ["playerctl", "--player=playerctld", "play-pause"]
    cmdProc.running = true
  }

  function next() {
    cmdProc.command = ["playerctl", "--player=playerctld", "next"]
    cmdProc.running = true
  }

  function youtubeThumb(url) {
    if (!url) return "";
    var match = url.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/)([a-zA-Z0-9_-]{11})/);
    return match ? "https://img.youtube.com/vi/" + match[1] + "/hqdefault.jpg" : "";
  }

  function fetchMetadata() {
    metaProc.running = false;
    metaProc.command = [
      "playerctl", "--player=playerctld", "metadata",
      "--format",
      "{{title}}|~|{{artist}}|~|{{mpris:artUrl}}|~|{{xesam:url}}|~|{{mpris:length}}|~|{{mpris:position}}"
    ];
    metaProc.running = true;
  }

  property Process statusProc: Process {
    command: ["playerctl", "-p", "playerctld", "status", "--follow"]
    running: true
    stdout: SplitParser {
      onRead: (data) => {
        playerctl.playing = data.trim() === "Playing"
        playerctl.fetchMetadata()
      }
    }
  }

  property Process cmdProc: Process {
    command: ["true"]
    running: false
  }

  property Process metaProc: Process {
    command: ["true"]
    running: false
    stdout: SplitParser {
      onRead: (data) => {
        var parts = data.trim().split("|~|")
        if (parts.length < 6) return
        playerctl.title = parts[0] || "No Media"
        playerctl.artist = parts[1] || "Unknown Artist"
        var artUrl = parts[2] || ""
        var pageUrl = parts[3] || ""
        var len = parseFloat(parts[4]) || 0
        var pos = parseFloat(parts[5]) || 0
        playerctl.length = len > 0 ? len / 1000000 : 1
        playerctl.position = pos > 0 ? pos / 1000000 : 0
        var newArt = ""
        if (artUrl.startsWith("/"))
          newArt = "file://" + artUrl
        else if (artUrl)
          newArt = artUrl
        else if (pageUrl)
          newArt = playerctl.youtubeThumb(pageUrl)
        if (newArt)
          playerctl.art = newArt
      }
    }
  }

  property Timer metaTimer: Timer {
    interval: 2000
    onTriggered: playerctl.fetchMetadata()
  }
}
