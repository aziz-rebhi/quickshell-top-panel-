pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

QtObject {
  id: _root

  property var cache: ({})
  property var _pending: []
  property var _currentItem: null

  function resolveIcon(name, callback) {
    if (!name) {
      if (callback) callback("");
      return;
    }
    if (name.indexOf("/") >= 0 || name.startsWith("file://")) {
      if (callback) callback(name);
      return;
    }

    if (name in cache) {
      var cached = cache[name];
      if (callback) callback(cached ? "file://" + cached : "");
      return;
    }

    _pending.push({ name: name, callback: callback });
    if (!_currentItem) _processNext();
  }

  function _processNext() {
    if (_pending.length === 0) {
      _currentItem = null;
      return;
    }
    _currentItem = _pending.shift();

    var escaped = _currentItem.name.replace(/'/g, "'\\''");
    resolver.command = [
      "sh", "-c",
      "XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}; " +
      "FLATPAK_USER=$HOME/.local/share/flatpak/exports/share; " +
      "ICON_DIRS=\"$XDG_DATA_HOME/icons /usr/local/share/icons /usr/share/icons " +
        "$HOME/.icons /var/lib/flatpak/exports/share/icons " +
        "$FLATPAK_USER/icons /usr/share/pixmaps\"; " +
      "i='$1'; " +
      "for idir in $ICON_DIRS; do " +
      "  for size in 512 256 128 96 64 48 32 24 16; do " +
      "    for ext in png svg svgz xpm jpg; do " +
      "      f=\"$idir/hicolor/${size}x${size}/apps/${i}.${ext}\"; " +
      "      [ -f \"$f\" ] && echo \"$f\" && exit 0; " +
      "    done; " +
      "  done; " +
      "done; " +
      "for ext in png svg svgz xpm jpg; do " +
      "  for idir in $ICON_DIRS; do " +
      "    f=\"$idir/hicolor/scalable/apps/${i}.${ext}\"; " +
      "    [ -f \"$f\" ] && echo \"$f\" && exit 0; " +
      "  done; " +
      "done; " +
      "for idir in $ICON_DIRS; do " +
      "  for ext in png svg; do " +
      "    f=$(find -L \"$idir\" -maxdepth 4 -name \"${i}.${ext}\" -print -quit 2>/dev/null); " +
      "    [ -n \"$f\" ] && echo \"$f\" && exit 0; " +
      "  done; " +
      "done; " +
      "for ext in png xpm svg; do " +
      "  [ -f \"/usr/share/pixmaps/${i}.${ext}\" ] && echo \"/usr/share/pixmaps/${i}.${ext}\" && exit 0; " +
      "done; " +
      "for idir in $ICON_DIRS; do " +
      "  [ -f \"$idir/${i}.png\" ] && { echo \"$idir/${i}.png\"; exit 0; }; " +
      "  [ -f \"$idir/${i}.svg\" ] && { echo \"$idir/${i}.svg\"; exit 0; }; " +
      "done; " +
      "echo ''",
      "sh", _currentItem.name
    ];
    resolver.running = true;
  }

  property Process resolver: Process {
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        var path = this.text.trim();
        var item = _currentItem;
        if (item) {
          if (path)
            _root.cache[item.name] = path;
          if (item.callback)
            item.callback(path ? "file://" + path : "");
        }
        _root._processNext();
      }
    }
  }
}
