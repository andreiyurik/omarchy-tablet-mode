import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The bar button and the panel it opens.
//
// The rotation itself needs no button: the accelerometer handles it. What the
// panel is for is everything a person folding the machine still wants a hand
// in -- freezing the orientation, turning it by hand, the pen -- and it has to
// work under a finger, since a folded machine has no mouse and no middle
// button. So a tap opens it, and every control in it is a full-width target.
Panel {
  id: root
  moduleName: "andreiyurik.tablet-mode"
  ipcTarget: "andreiyurik.tablet-mode"

  readonly property var service: {
    var host = bar && bar.shell ? bar.shell : null
    if (!host || typeof host.serviceFor !== "function") return null
    return host.serviceFor("andreiyurik.tablet-mode")
  }

  readonly property bool locked: service ? service.locked : false
  readonly property bool folded: service ? service.folded : false
  readonly property bool hasFoldSensor: service ? service.hasFoldSensor : true
  readonly property bool hasPen: service ? service.hasPen : false
  readonly property string orientation: service ? service.orientation : "normal"
  readonly property bool sensorAvailable: service ? service.sensorAvailable : true
  readonly property bool sensorInstalled: service ? service.sensorInstalled : true

  // ----------------------------------------------------------------- settings

  // The daemon reads these from shell.json itself and follows the file, so
  // saving one is all it takes to apply it.
  readonly property string mapping: setting("mapping", "auto")
  readonly property bool allPositions: setting("allPositions", false) === true
  readonly property bool hideInLaptopMode: setting("hideInLaptopMode", false) === true
  readonly property bool hideCursorWithPen: setting("hideCursorWithPen", false) === true
  readonly property string penPressure: setting("penPressure", "normal")

  function save(name, value) {
    var change = {}
    change[name] = value
    root.settings = Object.assign({}, root.settings, change)
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  // With a fold sensor and this setting on, the button stays out of the bar
  // until the machine is folded, since nothing rotates before then.
  visible: !hideInLaptopMode || !hasFoldSensor || folded || locked || opened
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string status: {
    if (!sensorInstalled) return "Needs iio-sensor-proxy"
    if (locked) return "Rotation locked"
    if (!sensorAvailable) return "Turned by hand"
    if (hasFoldSensor && !allPositions && !folded) return "Rotates once folded"
    return "Following the sensor"
  }

  readonly property string position: ({
    "normal": "landscape",
    "right-up": "portrait",
    "bottom-up": "landscape, upside down",
    "left-up": "portrait, the other way"
  })[orientation] || orientation

  // --------------------------------------------------------- keyboard cursor

  // The rows the cursor walks, top to bottom. Each has as many cells as it
  // has buttons; a toggle row has one.
  readonly property var rows: {
    var list = [{ id: "screen", cells: 3 }, { id: "allPositions", cells: 1 }]
    if (hasPen) list.push({ id: "hideCursor", cells: 1 }, { id: "pressure", cells: 3 })
    list.push({ id: "mapping", cells: mappingOptions.length })
    return list
  }
  property int cursorRow: 0
  property int cursorCell: 0
  property bool cursorActive: false

  function cursorOn(rowId, cell) {
    return cursorActive && rows[cursorRow] && rows[cursorRow].id === rowId
      && (cell === undefined || cursorCell === cell)
  }

  function point(rowId, cell) {
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].id !== rowId) continue
      cursorActive = true
      cursorRow = i
      cursorCell = cell || 0
    }
  }

  function moveCursor(dx, dy) {
    if (!cursorActive) { cursorActive = true; return }
    if (dy !== 0) {
      cursorRow = Math.max(0, Math.min(rows.length - 1, cursorRow + dy))
      cursorCell = Math.min(cursorCell, rows[cursorRow].cells - 1)
    } else {
      cursorCell = Math.max(0, Math.min(rows[cursorRow].cells - 1, cursorCell + dx))
    }
  }

  function activateCursor() {
    if (!cursorActive) return
    var row = rows[cursorRow].id
    if (row === "screen") screenActions[cursorCell].run()
    else if (row === "allPositions") save("allPositions", !allPositions)
    else if (row === "hideCursor") save("hideCursorWithPen", !hideCursorWithPen)
    else if (row === "pressure") save("penPressure", pressureOptions[cursorCell].value)
    else if (row === "mapping") save("mapping", mappingOptions[cursorCell].value)
  }

  onOpenedChanged: {
    if (!opened) return
    cursorActive = false
    cursorRow = 0
    cursorCell = 1
    if (service) service.refresh()
  }
  onRowsChanged: if (cursorRow >= rows.length) cursorRow = rows.length - 1

  // ------------------------------------------------------------------ choices

  // A Hyprland transform counts quarter turns counter-clockwise, so "next"
  // turns the picture left.
  // Icons: nf-md-rotate_left, nf-md-lock / nf-md-lock_open_variant,
  // nf-md-rotate_right.
  readonly property var screenActions: [
    { label: "Left", icon: "\u{F0465}", run: function() { if (root.service) root.service.rotate("next") } },
    { label: root.locked ? "Unlock" : "Lock", icon: root.locked ? "\u{F033E}" : "\u{F0FC6}",
      run: function() { if (root.service) root.service.toggleLock() } },
    { label: "Right", icon: "\u{F0467}", run: function() { if (root.service) root.service.rotate("prev") } }
  ]

  readonly property var pressureOptions: [
    { value: "soft", label: "Soft" },
    { value: "normal", label: "Normal" },
    { value: "firm", label: "Firm" }
  ]

  readonly property var mappingOptions: [
    { value: "auto", label: "Auto" },
    { value: "portrait-swapped", label: "Upright ⇄" },
    { value: "landscape-swapped", label: "Flat ⇄" },
    { value: "rotated-180", label: "180°" }
  ]

  // ------------------------------------------------------------------- button

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-md-screen_rotation_lock / nf-md-screen_rotation
    text: root.locked ? "\u{F0478}" : "\u{F0475}"
    active: root.locked
    tooltipText: root.opened ? "" : root.status
    // A tap opens the panel. With a mouse, the middle button still turns the
    // screen without opening anything.
    onPressed: function(b) {
      if (b === Qt.MiddleButton) { if (root.service) root.service.rotate("next") }
      else root.toggle()
    }
  }

  // -------------------------------------------------------------------- panel

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: icon · name and state · orientation ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.folded ? "\u{F04F6}" : "\u{F0322}"  // nf-md-tablet / nf-md-laptop
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: root.folded ? "Tablet" : (root.hasFoldSensor ? "Laptop" : "Screen")
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: (root.status + " · " + root.position).toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        // Without the package the sensor never shows up, which looks just
        // like a machine without one. Say what to do instead.
        Text {
          visible: !root.sensorInstalled
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "Turning with the machine needs the iio-sensor-proxy package. "
            + "Add it from the Omarchy menu, under Install › Package; "
            + "the screen starts following the sensor as soon as it is there."
          color: root.bar.foreground
          opacity: 0.8
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // ---------- Screen ----------
        Row {
          id: screenRow
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.screenActions
            Button {
              required property var modelData
              required property int index
              width: (screenRow.width - screenRow.spacing * 2) / 3
              iconText: modelData.icon
              iconSize: Style.font.iconLarge
              text: modelData.label
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              verticalPadding: Style.space(12)
              bordered: true
              active: index === 1 && root.locked
              hasCursor: root.cursorOn("screen", index)
              onClicked: modelData.run()
              onHovered: function(h) { if (h) root.point("screen", index) }
            }
          }
        }

        Toggle {
          width: parent.width
          label: "Rotate as a laptop too"
          description: root.hasFoldSensor
            ? "Off, the screen turns only once folded, so a laptop on your knees never flips."
            : "This machine has no fold sensor, so the screen turns in every position."
          checked: root.allPositions || !root.hasFoldSensor
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          hasCursor: root.cursorOn("allPositions")
          onClicked: root.save("allPositions", !root.allPositions)
          onHovered: function(h) { if (h) root.point("allPositions") }
        }

        // ---------- Pen ----------
        PanelSeparator {
          visible: root.hasPen
          foreground: root.bar.foreground
        }

        Column {
          visible: root.hasPen
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "PEN"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Toggle {
            width: parent.width
            label: "Hide the cursor while writing"
            description: "The pointer disappears while the pen is near the screen, and comes back when a mouse or touchpad moves."
            checked: root.hideCursorWithPen
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            hasCursor: root.cursorOn("hideCursor")
            onClicked: root.save("hideCursorWithPen", !root.hideCursorWithPen)
            onHovered: function(h) { if (h) root.point("hideCursor") }
          }

          PanelSectionHeader {
            text: "PRESSURE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          ChoiceRow {
            rowId: "pressure"
            options: root.pressureOptions
            value: root.penPressure
            onChosen: function(v) { root.save("penPressure", v) }
          }
        }

        // ---------- Mounting ----------
        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "SCREEN TURNS THE WRONG WAY?"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          ChoiceRow {
            rowId: "mapping"
            options: root.mappingOptions
            value: root.mapping === "standard" ? "auto" : root.mapping
            onChosen: function(v) { root.save("mapping", v) }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: "Pick the pair that comes out mirrored. If your model needs anything but Auto, "
              + "a machine report on the plugin's GitHub page makes Auto right for the next person."
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  // One of N, as a row of equal buttons wide enough for a finger.
  component ChoiceRow: Row {
    id: choice
    property string rowId: ""
    property var options: []
    property string value: ""
    signal chosen(string value)

    width: parent.width
    spacing: Style.space(6)

    Repeater {
      model: choice.options
      Button {
        required property var modelData
        required property int index
        width: (choice.width - choice.spacing * (choice.options.length - 1)) / choice.options.length
        text: modelData.label
        fontSize: Style.font.bodySmall
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        verticalPadding: Style.space(10)
        bordered: true
        active: choice.value === modelData.value
        hasCursor: root.cursorOn(choice.rowId, index)
        onClicked: choice.chosen(modelData.value)
        onHovered: function(h) { if (h) root.point(choice.rowId, index) }
      }
    }
  }
}
