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

  // Pushed by the widget from its settings; see manifest.json for what they mean.
  property string mapping: "standard"
  property bool allPositions: false

  // Observed state, refreshed from `omarchy-tablet-mode status`.
  property bool locked: false
  property int panelTransform: 0
  property string orientation: "normal"
  property bool folded: false
  property bool hasFoldSensor: true
  property bool sensorAvailable: true

  readonly property string cli: Qt.resolvedUrl("bin/omarchy-tablet-mode")
    .toString().replace("file://", "")

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

  // Settings only reach the daemon through its arguments, so a change has to
  // restart it. Nothing is lost: the daemon holds no state of its own.
  onMappingChanged: restartDaemon()
  onAllPositionsChanged: restartDaemon()

  function restartDaemon() {
    daemonProc.running = false
    daemonRestart.restart()
  }

  Component.onCompleted: {
    // Idempotent: it rewrites its own marked block in hyprland.lua and does
    // nothing when the block is already correct.
    setupProc.running = true
  }

  Process {
    id: setupProc
    command: [root.cli, "setup"]
    onExited: {
      daemonProc.running = true
      root.refresh()
    }
  }

  Process {
    id: daemonProc
    command: {
      var args = [root.cli, "daemon", "--mapping", root.mapping]
      if (root.allPositions) args.push("--all-positions")
      return args
    }
    stderr: SplitParser {
      // The daemon reports fold transitions; each one changes what the widget
      // should be showing.
      onRead: function(line) {
        root.sensorAvailable = line.indexOf("no accelerometer") === -1
                            && line.indexOf("unavailable") === -1
        root.refresh()
      }
    }
    onExited: if (root.sensorAvailable) daemonRestart.restart()
  }

  Timer {
    id: daemonRestart
    interval: 5000
    onTriggered: if (!daemonProc.running) daemonProc.running = true
  }

  Process {
    id: statusProc
    command: [root.cli, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var data
        try {
          data = JSON.parse(text || "{}")
        } catch (e) {
          return
        }
        root.locked = data.locked === true
        root.panelTransform = Number(data.transform) || 0
        root.orientation = data.orientation || "normal"
        root.folded = data.folded === true
        root.hasFoldSensor = data.hasFoldSensor === true
      }
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
      // The panel only ever moves through a config reload, so this is the one
      // event that can mean the orientation changed.
      if (event && String(event.name) === "configreloaded") root.refresh()
    }
  }

  // A backstop: the fold switch is sysfs, which raises no event of its own.
  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }
}
