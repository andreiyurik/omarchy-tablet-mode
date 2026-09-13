import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// The rotation daemon, mounted once for the shell.
//
// Omarchy builds a bar per monitor, so a Process living on the widget would be
// one daemon per screen, each claiming the accelerometer and each rotating the
// panel. The daemon and the state everything reads belong here.
Item {
  id: root
  width: 0
  height: 0
  visible: false

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null
  property string omarchyPath: ""

  // Observed state. The daemon prints it as a JSON line whenever it changes.
  property bool locked: false
  property int panelTransform: 0
  property string orientation: "normal"
  property bool folded: false
  property bool hasFoldSensor: true
  property bool sensorAvailable: true

  readonly property string cli: decodeURIComponent(
    Qt.resolvedUrl("bin/omarchy-tablet-mode").toString().replace("file://", ""))

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function toggleLock() {
    lockProc.command = [cli, "lock", "toggle"]
    lockProc.running = true
  }

  function rotate(position) {
    rotateProc.command = [cli, "rotate", position]
    rotateProc.running = true
  }

  function applyStatus(line) {
    var data
    try {
      data = JSON.parse(line)
    } catch (e) {
      return
    }
    root.locked = data.locked === true
    root.panelTransform = Number(data.transform) || 0
    root.orientation = data.orientation || "normal"
    root.folded = data.folded === true
    root.hasFoldSensor = data.hasFoldSensor === true
    if (data.sensor !== undefined) root.sensorAvailable = data.sensor === true
  }

  Component.onCompleted: {
    // Idempotent: it re-detects hardware, rewrites its own marked block in
    // hyprland.lua only when missing, and reloads only when something changed.
    setupProc.running = true
  }

  Process {
    id: setupProc
    command: [root.cli, "setup"]
    onExited: daemonProc.running = true
  }

  // The daemon reads the widget's settings from shell.json itself and follows
  // changes to them, so nothing here has to pass them on or restart it.
  Process {
    id: daemonProc
    command: [root.cli, "daemon"]
    stdout: SplitParser {
      onRead: function(line) { root.applyStatus(line) }
    }
    stderr: SplitParser {
      onRead: function(line) { console.info(line) }
    }
    // After a crash, come back. The pause keeps a daemon that fails at startup
    // from spinning.
    onExited: daemonRestart.restart()
  }

  Timer {
    id: daemonRestart
    interval: 2000
    onTriggered: if (!daemonProc.running) daemonProc.running = true
  }

  Process {
    id: statusProc
    command: [root.cli, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  Process {
    id: lockProc
    onExited: root.refresh()
  }

  Process {
    id: rotateProc
    onExited: root.refresh()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      // A reload replays the recorded orientation, which may differ from what
      // the widget last heard.
      if (event && String(event.name) === "configreloaded") root.refresh()
    }
  }
}
