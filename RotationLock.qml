import QtQuick
import Quickshell
import qs.Ui

// Rotation lock, the way a tablet has one.
//
// The rotation itself needs no button: the accelerometer handles it and a
// keybinding (see the README) covers the rest. What a button is genuinely for is freezing the
// orientation -- reading in bed, the machine tips, and the screen should stay
// where it is.
BarWidget {
  id: root
  moduleName: "andreiyurik.tablet-mode"

  readonly property var service: {
    var host = bar && bar.shell ? bar.shell : null
    if (!host || typeof host.serviceFor !== "function") return null
    return host.serviceFor("andreiyurik.tablet-mode")
  }

  readonly property bool locked: service ? service.locked : false
  readonly property bool folded: service ? service.folded : false
  readonly property bool hasFoldSensor: service ? service.hasFoldSensor : true
  readonly property string orientation: service ? service.orientation : "normal"
  readonly property bool sensorAvailable: service ? service.sensorAvailable : true

  // ----------------------------------------------------------------- settings

  readonly property string mapping: setting("mapping", "standard")
  readonly property bool allPositions: setting("allPositions", false)
  readonly property bool hideInLaptopMode: setting("hideInLaptopMode", false)

  function pushSettings() {
    if (!service) return
    service.mapping = mapping
    service.allPositions = allPositions
  }

  onMappingChanged: pushSettings()
  onAllPositionsChanged: pushSettings()
  onServiceChanged: pushSettings()
  Component.onCompleted: pushSettings()

  // With a fold sensor and this setting on, the widget stays out of the bar
  // until the machine is actually folded, since nothing rotates before then.
  visible: !hideInLaptopMode || !hasFoldSensor || folded || locked

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string tooltip: {
    if (locked)
      return "Rotation locked (" + orientation + ")"
    if (!sensorAvailable)
      return "No accelerometer: middle-click rotates by hand"
    if (hasFoldSensor && !allPositions && !folded)
      return "Auto-rotation waits for tablet mode"
    return "Following the accelerometer (" + orientation + ")"
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-md-screen_rotation_lock / nf-md-screen_rotation
    text: root.locked ? "󰔢" : "󰔡"
    active: root.locked
    tooltipText: root.tooltip
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.service && root.service.rotate("next")
      else root.service && root.service.toggleLock()
    }
  }
}
