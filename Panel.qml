pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui

// Bar button plus the settings popout for Theme RGB. All state lives in
// Service.qml (looked up through the shell); this file only shows it and
// forwards the user's choices. The preview strip is painted from the same
// `stops` the script sends to the hardware, so what you see is what lights.
Panel {
  id: themeRgb
  moduleName: "huacnlee.theme_rgb"
  // With two monitors there are two bars and two of this widget; the second
  // handler logs that it is unused, as the first-party panels' do.
  ipcTarget: "huacnlee.theme_rgb"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)

  property var service: null

  // One keyboard cursor: a row ("mode" | "swatch" | "brightness") and an
  // index within it. Pointer hover moves the same cursor.
  property string cursorRow: "mode"
  property int cursorIndex: 0
  property bool cursorActive: false

  readonly property var modes: [
    { value: "single", label: "Single", tooltip: "One theme colour on every device" },
    { value: "3", label: "3", tooltip: "Three colours: the chosen one plus the two nearest theme hues" },
    { value: "5", label: "5", tooltip: "Up to five: the chosen one plus the nearest theme hues within 90°" },
    { value: "custom", label: "Custom", tooltip: "Exactly the theme colours you pick, in that order" }
  ]

  readonly property string mode: service ? String(service.mode) : "palette"
  readonly property string modeValue: mode === "palette" ? String(service ? service.colors : 5) : mode
  readonly property var variables: service && service.variables ? service.variables : []
  readonly property var stops: service && service.stops ? service.stops : []
  readonly property var devices: service && service.devices ? service.devices : []
  readonly property var custom: service && service.custom ? service.custom : []
  readonly property int brightness: service ? service.brightness : 100
  readonly property bool openrgbPresent: service ? service.openrgbPresent : false
  readonly property bool syncing: service ? service.syncing : false

  // The variable the swatch row treats as selected in single-select modes.
  readonly property string selectedVariable: mode === "single"
    ? (service && service.single !== "" ? service.single : "accent")
    : (service ? service.anchor : "accent")

  // What is actually lit: a theme may not have five distinct hues to offer.
  // Anything that needs attention takes this line over.
  readonly property string metaText: {
    if (!service) return "Service not running"
    if (!openrgbPresent) return "OpenRGB is not installed"
    if (syncing) return "Syncing…"
    if (service.lastSyncFailed) return "Last sync failed"
    return stops.length <= 1 ? "One theme colour" : stops.length + " theme colours in bands"
  }
  readonly property string swatchHeading: mode === "single" ? "THEME COLOUR" : (mode === "custom" ? "COLOURS TO LIGHT" : "AROUND")
  readonly property string swatchHint: {
    if (mode === "single") return "The variable from colors.toml every device shows."
    if (mode === "custom") return "Any number, lit in the order picked."
    return "Joined by the theme colours nearest it in hue."
  }

  function lookupService() {
    if (!bar || !bar.shell || typeof bar.shell.serviceFor !== "function") return
    var found = bar.shell.serviceFor(moduleName)
    if (found) service = found
  }

  function chooseMode(value) {
    if (!service) return
    if (value === "single" || value === "custom") service.setMode(value)
    else { service.setColors(Number(value)); if (mode !== "palette") service.setMode("palette") }
  }

  function chooseVariable(name) {
    if (!service) return
    if (mode === "single") service.setSingle(name)
    else if (mode === "custom") service.toggleCustom(name)
    else service.setAnchor(name)
  }

  function isSwatchSelected(name) {
    if (mode === "custom") return custom.indexOf(name) !== -1
    return name === selectedVariable
  }

  function syncNow() {
    if (service && !syncing) service.apply()
  }

  function modeIndex() {
    for (var i = 0; i < modes.length; i++)
      if (modes[i].value === modeValue) return i
    return 0
  }

  function rowLength(row) {
    if (row === "mode") return modes.length
    if (row === "swatch") return variables.length
    return 1
  }

  function moveCursor(dx, dy) {
    var rows = ["mode", "swatch", "brightness"]
    var r = rows.indexOf(cursorRow)
    if (dy !== 0) {
      r = Math.max(0, Math.min(rows.length - 1, r + dy))
      cursorRow = rows[r]
      cursorIndex = Math.min(cursorIndex, Math.max(0, rowLength(cursorRow) - 1))
      return
    }
    if (cursorRow === "brightness") {
      if (service) service.setBrightness(brightness + dx * 10)
      return
    }
    var len = rowLength(cursorRow)
    if (len === 0) return
    cursorIndex = (cursorIndex + dx + len) % len
  }

  function activateCursor() {
    if (cursorRow === "mode") chooseMode(modes[cursorIndex].value)
    else if (cursorRow === "swatch" && variables[cursorIndex]) chooseVariable(variables[cursorIndex].name)
  }

  // Bar icon --------------------------------------------------------------

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: themeRgb.bar
    tooltipText: "Theme RGB · " + themeRgb.metaText

    readonly property color glyphColor: themeRgb.openrgbPresent
      ? themeRgb.barForeground
      : Qt.darker(themeRgb.barForeground, 1.55)

    iconComponent: Component {
      Item {
        OpticalGlyph {
          anchors.centerIn: parent
          text: "󰏘"
          color: button.glyphColor
          fontFamily: themeRgb.fontFamily
          fontSize: Style.font.icon
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) themeRgb.toggle()
    }
  }

  Component.onCompleted: lookupService()
  onBarChanged: lookupService()

  onOpenedChanged: if (opened) {
    lookupService()
    if (service) { service.refreshVariables(); service.refreshStops() }
    cursorActive = false
    cursorRow = "mode"
    cursorIndex = modeIndex()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // Popout ----------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: themeRgb
    bar: themeRgb.bar
    open: themeRgb.opened
    focusTarget: keyCatcher
    // Wide enough for the five mode chips in one row at any font size; the
    // Row's laid-out width is what the chips actually take.
    contentWidth: panel.fittedContentWidth(Math.max(Style.space(360), modeGroup.width))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(900))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (!themeRgb.cursorActive) { themeRgb.cursorActive = true; return }
        themeRgb.moveCursor(dx, dy)
      }
      onActivateRequested: if (themeRgb.cursorActive) themeRgb.activateCursor()
      onCloseRequested: themeRgb.close()
      onTabRequested: function(direction) { themeRgb.switchPanel(direction) }
      onTextKey: function(text) {
        var key = String(text || "").toLowerCase()
        if (key >= "1" && key <= "4") themeRgb.chooseMode(themeRgb.modes[Number(key) - 1].value)
        else if (key === "r") themeRgb.syncNow()
      }

      // Scrolls when a long device list outgrows the screen.
      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

      Column {
        id: column
        width: panelFlick.width
        spacing: Style.space(12)

        PanelHero {
          id: hero
          width: parent.width
          title: "Theme RGB"
          meta: themeRgb.metaText
          foreground: themeRgb.foreground
          fontFamily: themeRgb.fontFamily
          iconOpacity: themeRgb.openrgbPresent ? 1.0 : 0.5
          iconComponent: Component {
            Text {
              text: "󰏘"
              color: hero.foreground
              font.family: themeRgb.fontFamily
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: Component {
            PanelActionButton {
              iconText: "󰑐"
              tooltipText: themeRgb.syncing ? "Syncing…" : "Sync now (r)"
              foreground: themeRgb.foreground
              fontFamily: themeRgb.fontFamily
              enabled: themeRgb.openrgbPresent && !themeRgb.syncing
              onClicked: themeRgb.syncNow()
            }
          }
        }

        PanelSeparator { width: parent.width; foreground: themeRgb.foreground }

        // Mode ------------------------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "COLOURS"
            foreground: themeRgb.foreground
            fontFamily: themeRgb.fontFamily
          }

          ButtonGroup {
            id: modeGroup
            options: themeRgb.modes
            value: themeRgb.modeValue
            foreground: themeRgb.foreground
            fontFamily: themeRgb.fontFamily
            focusable: false
            cursorIndex: themeRgb.cursorActive && themeRgb.cursorRow === "mode" ? themeRgb.cursorIndex : -1
            onChanged: function(v) { themeRgb.chooseMode(v) }
            onHovered: function(index, isHovered) {
              if (!isHovered) return
              themeRgb.cursorActive = true
              themeRgb.cursorRow = "mode"
              themeRgb.cursorIndex = index
            }
          }
        }

        // Variables -------------------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: themeRgb.swatchHeading
            foreground: themeRgb.foreground
            fontFamily: themeRgb.fontFamily
          }

          Flow {
            id: swatchFlow
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: themeRgb.variables

              delegate: Item {
                id: swatch
                required property int index
                required property var modelData

                readonly property bool selected: themeRgb.isSwatchSelected(modelData.name)
                readonly property bool hot: themeRgb.cursorActive && themeRgb.cursorRow === "swatch" && themeRgb.cursorIndex === index
                readonly property int customOrder: themeRgb.custom.indexOf(modelData.name)

                // Sized to its content, like a chip.
                width: Style.space(8) + chip.width + Style.space(6) + label.implicitWidth + Style.space(8)
                height: Style.spacing.controlHeight

                // Quiet at rest; the shared hover and selected fills otherwise.
                Rectangle {
                  anchors.fill: parent
                  color: swatch.selected
                    ? Qt.rgba(themeRgb.foreground.r, themeRgb.foreground.g, themeRgb.foreground.b, 0.18)
                    : (swatch.hot ? Qt.rgba(themeRgb.foreground.r, themeRgb.foreground.g, themeRgb.foreground.b, 0.08) : "transparent")
                  border.width: swatch.selected ? 1 : 0
                  border.color: themeRgb.foreground
                }

                // The colour itself, as the theme defines it.
                Rectangle {
                  id: chip
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(14)
                  height: Style.space(14)
                  color: swatch.modelData.hex
                  border.width: 1
                  border.color: Qt.rgba(themeRgb.foreground.r, themeRgb.foreground.g, themeRgb.foreground.b, 0.25)

                  // In custom mode the order picked is the order lit.
                  Text {
                    anchors.centerIn: parent
                    visible: themeRgb.mode === "custom" && swatch.customOrder !== -1
                    text: String(swatch.customOrder + 1)
                    color: Qt.darker(swatch.modelData.hex, 3.0)
                    font.family: themeRgb.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }

                Text {
                  id: label
                  anchors.left: chip.right
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  text: swatch.modelData.name
                  color: themeRgb.foreground
                  font.family: themeRgb.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: swatch.selected
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: {
                    themeRgb.cursorActive = true
                    themeRgb.cursorRow = "swatch"
                    themeRgb.cursorIndex = swatch.index
                  }
                  onClicked: themeRgb.chooseVariable(swatch.modelData.name)
                }
              }
            }
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: themeRgb.variables.length === 0 ? "This theme has no colors.toml." : themeRgb.swatchHint
            color: themeRgb.dim
            font.family: themeRgb.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // Brightness ------------------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(8)

          Item {
            width: parent.width
            height: brightnessHeader.implicitHeight

            PanelSectionHeader {
              id: brightnessHeader
              anchors.left: parent.left
              text: "BRIGHTNESS"
              foreground: themeRgb.foreground
              fontFamily: themeRgb.fontFamily
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: themeRgb.brightness + "%"
              color: themeRgb.cursorActive && themeRgb.cursorRow === "brightness" ? themeRgb.foreground : themeRgb.dim
              font.family: themeRgb.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          PanelSlider {
            id: brightnessSlider
            bar: themeRgb.bar
            width: parent.width
            minimum: 10
            maximum: 100
            step: 5
            integer: true
            value: themeRgb.brightness
            onReleased: function(v) { if (themeRgb.service) themeRgb.service.setBrightness(v) }
          }
        }

        // Preview: the stops as bands, the way a strip of LEDs shows them.
        Rectangle {
          id: preview
          width: parent.width
          height: Style.space(18)
          color: "transparent"
          border.width: 1
          border.color: Qt.rgba(themeRgb.foreground.r, themeRgb.foreground.g, themeRgb.foreground.b, 0.40)

          Row {
            id: previewRow
            anchors.fill: parent
            anchors.margins: 1
            Repeater {
              model: themeRgb.stops
              delegate: Rectangle {
                required property var modelData
                width: Math.floor(previewRow.width / Math.max(1, themeRgb.stops.length))
                height: previewRow.height
                color: modelData
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: themeRgb.stops.length === 0
            text: "No colour for this theme"
            color: themeRgb.dim
            font.family: themeRgb.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        PanelSeparator { width: parent.width; foreground: themeRgb.foreground }

        // Devices ---------------------------------------------------------
        Column {
          id: devicesColumn
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "DEVICES"
            foreground: themeRgb.foreground
            fontFamily: themeRgb.fontFamily
          }

          Repeater {
            model: themeRgb.devices
            delegate: Item {
              id: deviceRow
              required property var modelData
              width: devicesColumn.width
              height: deviceName.implicitHeight + Style.space(4)

              Text {
                id: deviceName
                anchors.left: deviceRow.left
                anchors.right: deviceLeds.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: deviceRow.verticalCenter
                text: deviceRow.modelData.name
                elide: Text.ElideRight
                color: themeRgb.foreground
                font.family: themeRgb.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                id: deviceLeds
                anchors.right: deviceRow.right
                anchors.verticalCenter: deviceRow.verticalCenter
                text: [deviceRow.modelData.type, deviceRow.modelData.leds > 0 ? deviceRow.modelData.leds + " LEDs" : ""]
                  .filter(function(v) { return v !== "" }).join(" · ")
                color: themeRgb.dim
                font.family: themeRgb.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Text {
            visible: themeRgb.devices.length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            text: !themeRgb.openrgbPresent
              ? "Install OpenRGB to light devices (the openrgb package)."
              : (themeRgb.syncing ? "Looking for devices…" : "OpenRGB found no devices on the last sync.")
            color: themeRgb.dim
            font.family: themeRgb.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
      }
    }
  }
}
