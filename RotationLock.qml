import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The bar button and the panel it opens.
//
// Named for the rotation lock it began as. The name stays: the shell caches
// the plugin's directory, so an entry point under a new name fails to load
// after `omarchy plugin update` until the shell restarts, while a file that
// keeps its name goes on working in its old form until then.
//
// The rotation itself needs no button: the accelerometer handles it. What the
// panel is for is the two things a person holding a folded machine still
// reaches for -- the on-screen keyboard, and freezing or turning the screen --
// and it has to work under a finger, since a folded machine has no mouse and
// no middle button. So a tap opens it, and every control in it is a big
// target. Settings made once and then forgotten wait behind a button at the
// bottom, out of the way but still within a finger's reach, since the shell
// offers no other place to change them.
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
  readonly property string orientation: service ? service.orientation : "normal"
  readonly property bool sensorAvailable: service ? service.sensorAvailable : true
  readonly property bool sensorInstalled: service ? service.sensorInstalled : true
  readonly property string keyboard: service ? service.keyboard : ""

  // ----------------------------------------------------------------- settings

  // The daemon reads these from shell.json itself and follows the file, so
  // saving one is all it takes to apply it.
  readonly property string mapping: setting("mapping", "auto")
  readonly property bool allPositions: setting("allPositions", false) === true
  readonly property bool keyboardOnFold: setting("keyboardOnFold", true) === true

  function save(name, value) {
    var change = {}
    change[name] = value
    root.settings = Object.assign({}, root.settings, change)
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  // Open as a laptop, nothing turns and the keyboard is the real one, so the
  // button stays out of the bar until the machine folds. It stays while a
  // lock is held, so the lock can be let go, and wherever the screen turns
  // as a laptop too.
  visible: !hasFoldSensor || allPositions || folded || locked || opened
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
    var list = []
    if (keyboard !== "") list.push({ id: "keyboardToggle", cells: 1 })
    list.push({ id: "screen", cells: 3 }, { id: "settings", cells: 1 })
    if (settingsShown) {
      list.push({ id: "allPositions", cells: 1 })
      if (keyboard !== "") list.push({ id: "keyboardOnFold", cells: 1 })
      list.push({ id: "mapping", cells: mappingOptions.length })
    }
    return list
  }
  property bool settingsShown: false
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
    else if (row === "settings") settingsShown = !settingsShown
    else if (row === "allPositions") save("allPositions", !allPositions)
    else if (row === "keyboardOnFold") save("keyboardOnFold", !keyboardOnFold)
    else if (row === "keyboardToggle") { if (service) service.toggleKeyboard() }
    else if (row === "mapping") save("mapping", mappingOptions[cursorCell].value)
  }

  onOpenedChanged: {
    if (!opened) return
    cursorActive = false
    settingsShown = false
    cursorRow = 0
    cursorCell = 0
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

        // ---------- Keyboard ----------
        // First, and the width of the panel: it is what a folded machine is
        // reached for most, and it has to be found without reading.
        Button {
          visible: root.keyboard !== ""
          width: parent.width
          iconText: "\u{F030C}"  // nf-md-keyboard
          iconSize: Style.font.iconLarge
          text: "Keyboard"
          fontSize: Style.font.body
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          verticalPadding: Style.space(16)
          bordered: true
          hasCursor: root.cursorOn("keyboardToggle")
          onClicked: { if (root.service) root.service.toggleKeyboard() }
          onHovered: function(h) { if (h) root.point("keyboardToggle") }
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

        // Nothing to bring up yet. Say which keyboards folding works with.
        Text {
          visible: root.keyboard === ""
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "For typing while folded, add an on-screen keyboard from plugins.omarchy.org, "
            + "such as On-Screen Keyboard or Omaqwerty. It comes up as you fold the machine."
          color: root.bar.foreground
          opacity: 0.6
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        // ---------- Settings ----------
        // Set once, if ever. Folded away until asked for.
        Button {
          width: parent.width
          iconText: root.settingsShown ? "\u{F0143}" : "\u{F0140}"  // nf-md-chevron_up / _down
          text: "Settings"
          fontSize: Style.font.bodySmall
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          verticalPadding: Style.space(10)
          hasCursor: root.cursorOn("settings")
          onClicked: root.settingsShown = !root.settingsShown
          onHovered: function(h) { if (h) root.point("settings") }
        }

        Column {
          visible: root.settingsShown
          width: parent.width
          spacing: Style.space(10)

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

          Toggle {
            visible: root.keyboard !== ""
            width: parent.width
            label: "Keyboard when folded"
            description: root.keyboard + " comes up as you fold the machine, and goes away as you open it."
            checked: root.keyboardOnFold
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            hasCursor: root.cursorOn("keyboardOnFold")
            onClicked: root.save("keyboardOnFold", !root.keyboardOnFold)
            onHovered: function(h) { if (h) root.point("keyboardOnFold") }
          }

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
