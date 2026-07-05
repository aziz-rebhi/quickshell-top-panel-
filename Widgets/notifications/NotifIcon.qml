import QtQuick
import Quickshell.Io
import "../../core"

Item {
  id: root

  required property string appIcon
  required property string appName

  property int iconSize: 42
  property string _resolvedSource: ""

  implicitWidth: iconSize
  implicitHeight: iconSize

  Image {
    id: iconImg
    anchors.fill: parent
    source: root._resolvedSource
    asynchronous: true
    sourceSize.width: root.iconSize * 2
    sourceSize.height: root.iconSize * 2
    visible: status === Image.Ready
    fillMode: Image.PreserveAspectFit
  }

  Rectangle {
    id: fallbackCircle
    anchors.fill: parent
    radius: width / 2
    visible: iconImg.status !== Image.Ready && (root.appIcon || root.appName)
    color: root.appIcon ? Theme.primary : "transparent"

    Text {
      anchors.centerIn: parent
      text: root.appName ? root.appName.charAt(0).toUpperCase() : "?"
      color: Theme.text
      font { family: "Inter"; pixelSize: parent.width * 0.45; weight: 700 }
    }
  }

  function startResolve(name) {
    if (!name || name.indexOf("/") >= 0 || name.startsWith("file://")) {
      root._resolvedSource = name.indexOf("/") >= 0 && !name.startsWith("file://")
        ? "file://" + name : (name || "");
      return;
    }
    var cmd = [
      "sh", "-c",
      "i=$1;" +
      "for d in /usr/share/icons/hicolor/*/apps /usr/share/pixmaps; do " +
      "  for f in \"$d/${i}.png\" \"$d/${i}.svg\" \"$d/${i}.xpm\"; do " +
      "    [ -f \"$f\" ] && echo \"$f\" && exit 0; " +
      "  done; " +
      "done; " +
      "echo ''",
      "sh", name
    ];
    resolver.command = cmd;
    resolver.running = true;
  }

  Process {
    id: resolver
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        var path = this.text.trim();
        root._resolvedSource = path ? "file://" + path : "";
      }
    }
  }

  onAppIconChanged: startResolve(appIcon)

  Component.onCompleted: {
    if (appIcon) startResolve(appIcon);
  }
}
