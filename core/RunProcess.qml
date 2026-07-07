pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
  function run(cmd, parent) {
    var p = Qt.createQmlObject(
      'import QtQuick; import Quickshell.Io; Process { command: ' + JSON.stringify(cmd) + ' }',
      parent || null
    );
    p.exited.connect(function() { p.destroy(); });
    p.running = true;
    return p;
  }
}
