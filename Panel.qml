pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "components"

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

  // One keyboard cursor: a row ("mode" | "layout" | "brightness") and an
  // index within it. Pointer hover moves the same cursor.
  property string cursorRow: "mode"
  property int cursorIndex: 0
  property bool cursorActive: false

  // The header's "more" menu, once its trailing control has loaded. While it
  // is open the list owns the keys.
  property var headerMenu: null
  readonly property bool menuOpen: headerMenu ? headerMenu.opened : false
  readonly property string githubUrl: "https://github.com/huacnlee/omarchy-theme-rgb"

  readonly property var modes: [
    { value: "single", label: "1", tooltip: "One theme colour on every device — the accent unless you pick another" },
    { value: "3", label: "3", tooltip: "Three colours: accent, background, foreground" },
    { value: "5", label: "Default", tooltip: "Five colours: those three plus two more, chosen by what each device is for" },
    { value: "8", label: "8", tooltip: "Eight: the theme's named colours in order, by what each device is for" }
  ]

  readonly property string mode: service ? String(service.mode) : "palette"
  readonly property string modeValue: mode === "palette" ? String(service ? service.colors : 5) : mode
  readonly property var variables: service && service.variables ? service.variables : []
  readonly property var stops: service && service.deskStops ? service.deskStops : []
  readonly property var ambientStops: service && service.ambientStops ? service.ambientStops : []
  readonly property int colors: service ? service.colors : 5
  readonly property var devices: service && service.devices ? service.devices : []
  readonly property int brightness: service ? service.brightness : 100
  readonly property bool openrgbPresent: service ? service.openrgbPresent : false
  readonly property bool syncing: service ? service.syncing : false

  // What is actually lit: a theme may not have five distinct hues to offer.
  // Anything that needs attention takes this line over.
  readonly property string slogan: "Your theme, on every light."
  // The slogan, unless something needs attention.
  readonly property string metaText: {
    if (!service) return "Service not running"
    if (!openrgbPresent) return "OpenRGB is not installed"
    if (syncing) return "Syncing…"
    if (service.lastSyncFailed) return "Last sync failed"
    return slogan
  }
  readonly property string modeHint: {
    if (mode === "single") return "The accent on every device."
    if (modeValue === "3") return "The accent and two of the theme's colours."
    if (modeValue === "8") return "Eight of the theme's colours; the desk and what is around it get their own order."
    return "Five of the theme's colours; the desk (keyboard, mouse) and what is around it (screen, case) get their own order."
  }
  readonly property string layout: service ? String(service.layout) : "flow"
  readonly property var layouts: [
    { value: "flow", label: "Flow", tooltip: "Bands along the LED order — top to bottom on most keyboards" },
    { value: "rows", label: "Rows", tooltip: "Keyboard rows top to bottom, by where each key sits" },
    { value: "columns", label: "Columns", tooltip: "Left to right across the keyboard, by where each key sits" },
    { value: "zones", label: "Zones", tooltip: "Function keys, main block, modifiers, navigation, numpad, logo; other devices by their OpenRGB zones" }
  ]
  readonly property string layoutHint: stops.length <= 1
    ? "One colour needs no layout."
    : stops.length + " colours" + (layout === "zones" ? " over the zones of each device." : " in bands, " + (layout === "flow" ? "along each device's LEDs." : (layout === "rows" ? "top to bottom." : "left to right.")))
  function lookupService() {
    if (!bar || !bar.shell || typeof bar.shell.serviceFor !== "function") return
    var found = bar.shell.serviceFor(moduleName)
    if (found) service = found
  }

  function chooseMode(value) {
    if (!service) return
    if (value === "single") service.setMode(value)
    else service.setPalette(Number(value))
  }

  function chooseLayout(value) {
    if (service) service.setLayout(value)
  }

  function syncNow() {
    if (service && !syncing) service.apply()
  }

  // The actions that do not earn a control of their own.
  readonly property var menuEntries: [
    { id: "sync", label: "Sync now", enabled: openrgbPresent && !syncing },
    { separator: true },
    { id: "github", label: "GitHub", enabled: true }
  ]

  function runMenuAction(id) {
    if (id === "sync") syncNow()
    else if (id === "github") { Quickshell.execDetached(["xdg-open", githubUrl]); close() }
  }

  function installOpenrgb() {
    if (service && !openrgbPresent) service.installOpenrgb()
  }

  function openMenu() {
    if (headerMenu && !menuOpen) headerMenu.open()
  }

  function modeIndex() {
    for (var i = 0; i < modes.length; i++)
      if (modes[i].value === modeValue) return i
    return 0
  }

  readonly property var cursorRows: ["mode", "layout", "brightness"]

  function rowLength(row) {
    if (row === "mode") return modes.length
    if (row === "layout") return layouts.length
    return 1
  }

  function moveCursor(dx, dy) {
    var rows = cursorRows
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
    else if (cursorRow === "layout") chooseLayout(layouts[cursorIndex].value)
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
    contentWidth: panel.fittedContentWidth(Math.max(Style.space(360), modeGroup.width, layoutGroup.width))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(900))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The open menu takes every key, Esc included, so Esc closes the menu
      // before it closes the panel and j/k walk the list, not the chips.
      blocked: themeRgb.menuOpen

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
        else if (key === "m") themeRgb.openMenu()
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
            Row {
              spacing: Style.space(2)

              PanelActionButton {
                iconText: "󰑐"
                tooltipText: themeRgb.syncing ? "Syncing…" : "Sync now (r)"
                foreground: themeRgb.foreground
                fontFamily: themeRgb.fontFamily
                enabled: themeRgb.openrgbPresent && !themeRgb.syncing
                onClicked: themeRgb.syncNow()
              }

              PanelMenu {
                id: moreMenu
                tooltipText: "More (m)"
                foreground: themeRgb.foreground
                fontFamily: themeRgb.fontFamily
                entries: themeRgb.menuEntries
                panelOpen: themeRgb.opened
                onActivated: function(id) { themeRgb.runMenuAction(id) }
                // Closing the list hands the keys back to the panel.
                onOpenedChanged: if (!opened && themeRgb.opened) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
                Component.onCompleted: themeRgb.headerMenu = moreMenu
                Component.onDestruction: if (themeRgb.headerMenu === moreMenu) themeRgb.headerMenu = null
              }
            }
          }
        }

        PanelSeparator { width: parent.width; foreground: themeRgb.foreground }

        // Welcome: nothing to set up until OpenRGB is installed --------------
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: !themeRgb.openrgbPresent

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Theme RGB lights your keyboard, mouse, RAM, fans and strips in the colours of the current theme, on every theme switch and at login. It drives them through OpenRGB, which is not installed yet."
            color: themeRgb.foreground
            font.family: themeRgb.fontFamily
            font.pixelSize: Style.font.body
          }

          Button {
            text: "Install OpenRGB"
            iconText: "󰏔"
            bordered: true
            foreground: themeRgb.foreground
            fontFamily: themeRgb.fontFamily
            enabled: !!themeRgb.service
            onClicked: themeRgb.installOpenrgb()
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Installs the openrgb package in a terminal. Once it is in place this panel switches to the colour settings by itself."
            color: themeRgb.dim
            font.family: themeRgb.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // Settings ----------------------------------------------------------
        Column {
          id: settings
          width: parent.width
          spacing: Style.space(12)
          visible: themeRgb.openrgbPresent

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

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: themeRgb.modeHint
            color: themeRgb.dim
            font.family: themeRgb.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // Layout ----------------------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(8)
          opacity: themeRgb.stops.length > 1 ? 1.0 : 0.5

          PanelSectionHeader {
            text: "LAYOUT"
            foreground: themeRgb.foreground
            fontFamily: themeRgb.fontFamily
          }

          ButtonGroup {
            id: layoutGroup
            options: themeRgb.layouts
            value: themeRgb.layout
            foreground: themeRgb.foreground
            fontFamily: themeRgb.fontFamily
            focusable: false
            cursorIndex: themeRgb.cursorActive && themeRgb.cursorRow === "layout" ? themeRgb.cursorIndex : -1
            onChanged: function(v) { themeRgb.chooseLayout(v) }
            onHovered: function(index, isHovered) {
              if (!isHovered) return
              themeRgb.cursorActive = true
              themeRgb.cursorRow = "layout"
              themeRgb.cursorIndex = index
            }
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: themeRgb.layoutHint
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

        // Preview: the stops as bands, the way a strip of LEDs shows them —
        // one strip per device class when they differ.
        Repeater {
          model: themeRgb.mode === "palette"
            ? [{ label: "Desk", colors: themeRgb.stops }, { label: "Around", colors: themeRgb.ambientStops }]
            : [{ label: "", colors: themeRgb.stops }]

          delegate: Item {
            id: preview
            required property var modelData
            width: settings.width
            height: Style.space(18)

            Text {
              id: previewLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: preview.modelData.label === "" ? 0 : Style.space(52)
              text: preview.modelData.label
              color: themeRgb.dim
              font.family: themeRgb.fontFamily
              font.pixelSize: Style.font.caption
            }

            Rectangle {
              anchors.left: previewLabel.right
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              color: "transparent"
              border.width: 1
              border.color: Qt.rgba(themeRgb.foreground.r, themeRgb.foreground.g, themeRgb.foreground.b, 0.40)

              Row {
                id: previewRow
                anchors.fill: parent
                anchors.margins: 1
                Repeater {
                  model: preview.modelData.colors
                  delegate: Rectangle {
                    required property var modelData
                    width: Math.floor(previewRow.width / Math.max(1, preview.modelData.colors.length))
                    height: previewRow.height
                    color: modelData
                  }
                }
              }

              Text {
                anchors.centerIn: parent
                visible: preview.modelData.colors.length === 0
                text: "No colour for this theme"
                color: themeRgb.dim
                font.family: themeRgb.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
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
}
