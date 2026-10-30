pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "components"
import "Routing.js" as Routing

// Bar button plus the settings popout for Theme RGB. All state lives in
// Service.qml (looked up through the shell); this file only shows it and
// forwards the user's choices. The numbered swatches, each device's colours
// and the keyboard drawing come from the script that lights the hardware, so
// what you see is what lights. Colours are numbered once, at the top; every
// device then says which numbers it shows.
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

  // One keyboard cursor: a section (mode, brightness, layout) and an index
  // within it. Pointer hover moves the same cursor. A device's dropdown takes
  // the keys while it is open.
  property string cursorRow: "mode"
  property int cursorIndex: 0
  property bool cursorActive: false
  property int openDropdowns: 0
  // The pattern under the pointer, described in place of the chosen one.
  property string hoveredLayout: ""

  // The header's "more" menu, once its trailing control has loaded. While it
  // is open the list owns the keys.
  property var headerMenu: null
  readonly property bool menuOpen: headerMenu ? headerMenu.opened : false
  readonly property string githubUrl: "https://github.com/huacnlee/omarchy-theme-rgb"

  readonly property var modes: [
    { value: "single", label: "1", tooltip: "Only the accent" },
    { value: "3", label: "3", tooltip: "The accent and the two theme colours closest to the wallpaper" },
    { value: "5", label: "5", tooltip: "Five theme colours, the wallpaper's first" },
    { value: "8", label: "8", tooltip: "Eight theme colours, the wallpaper's first" }
  ]

  readonly property string mode: service ? String(service.mode) : "palette"
  readonly property string modeValue: mode === "palette" ? String(service ? service.colors : 8) : mode
  readonly property var variables: service && service.variables ? service.variables : []
  readonly property var stops: service && service.deskStops ? service.deskStops : []
  readonly property var keyboardRows: {
    var keys = service ? service.keyboardPreview : []
    var rows = []
    for (var i = 0; i < keys.length; i++) if (rows.indexOf(keys[i].row) < 0) rows.push(keys[i].row)
    return rows.sort(function(a,b) { return a-b })
  }
  readonly property var keyboardBounds: {
    var keys = service ? service.keyboardPreview : []
    var lo = 100, hi = 0
    for (var i = 0; i < keys.length; i++) {
      var x = keys[i].name === "Space" ? 4.5 : keys[i].column
      lo = Math.min(lo, x)
      hi = Math.max(hi, x + (keys[i].name === "Space" ? 5.75 : 1))
    }
    return { left: lo === 100 ? 0 : lo, width: Math.max(1, hi-lo) }
  }
  readonly property int colors: service ? service.colors : 8
  // Every device and what it lights (Routing.parsePlan rows).
  readonly property var plan: Routing.parsePlan(service ? service.planText : "")
  readonly property var openrgbRows: plan.filter(function(r) { return r.source === "openrgb" })
  readonly property var hassRows: plan.filter(function(r) { return r.source === "hass" })
  readonly property string hassStatus: service ? service.hassStatus : ""
  readonly property string hassMessage: Routing.hassMessage(hassStatus, hassRows.length)
  readonly property bool patternInUse: Routing.patternInUse(plan, stops.length)
  readonly property var skippedDetectors: service && service.skippedDetectors ? service.skippedDetectors : []
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
  readonly property string layout: service ? String(service.layout) : "omarchy"
  readonly property var layouts: [
    { value: "omarchy", label: "Omarchy", tooltip: "Colour 1 on the letters; Super, the modifiers, numbers and arrows, punctuation, Esc, Delete and Enter stand out in the other colours." },
    { value: "flow", label: "Flow", tooltip: "Even bands in LED order, colour 1 first: top to bottom on most keyboards, end to end on a strip." },
    { value: "rows", label: "Rows", tooltip: "One colour per keyboard row, colour 1 at the top." },
    { value: "columns", label: "Columns", tooltip: "Bands from left to right across the keyboard, colour 1 on the left." },
    { value: "zones", label: "Zones", tooltip: "Function keys (colour 1), letters, modifiers, navigation, numpad and logo in turn; a mouse or pad by its own zones." },
    { value: "gaming", label: "Gaming", tooltip: "A dimmed colour 1 underneath; WASD, the arrows and skill keys 1–5 in vivid colours (fills up to eight)." },
    { value: "outline", label: "Frame", tooltip: "Colour 1 inside; the outer rows and side keys of the letter block in the other colours." },
    { value: "lazyvim", label: "LazyVim", tooltip: "Colour 1 everywhere; HJKL, and Space with Esc, stand out in the other colours." }
  ]
  function layoutInfo(value) {
    for (var i = 0; i < layouts.length; i++) if (layouts[i].value === value) return layouts[i]
    return layouts[0]
  }
  readonly property var shownLayout: layoutInfo(hoveredLayout !== "" ? hoveredLayout : layout)
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

  readonly property var cursorRows: ["mode", "brightness", "layout"]

  function rowLength(row) {
    if (row === "mode") return modes.length
    if (row === "layout") return layouts.length
    return 1
  }

  function moveCursor(dx, dy) {
    var rows = cursorRows
    var r = rows.indexOf(cursorRow)
    if (dy !== 0) {
      if (cursorRow === "layout") {
        var current = layoutButtons.itemAt(cursorIndex)
        var best = -1, distance = Infinity
        if (current) {
          for (var i = 0; i < layouts.length; i++) {
            var item = layoutButtons.itemAt(i)
            if (!item || (item.y - current.y) * dy <= 0) continue
            var d = Math.abs(item.y - current.y) * 1000 + Math.abs(item.x + item.width / 2 - current.x - current.width / 2)
            if (d < distance) { distance = d; best = i }
          }
        }
        if (best >= 0) { cursorIndex = best; return }
      }
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

  // One device: the colours it shows, its name, and the choice of which.
  component DeviceRow: Item {
    id: deviceRow
    required property var modelData
    readonly property int count: themeRgb.stops.length
    height: Math.max(deviceText.implicitHeight, choice.height) + Style.space(2)

    Rectangle {
      id: deviceSwatch
      anchors.left: deviceRow.left
      anchors.verticalCenter: deviceRow.verticalCenter
      width: Style.space(36)
      height: Style.space(16)
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(themeRgb.foreground.r, themeRgb.foreground.g, themeRgb.foreground.b, 0.35)
      Row {
        id: deviceBands
        anchors.fill: parent
        anchors.margins: 1
        Repeater {
          model: deviceRow.modelData.colours
          delegate: Rectangle {
            required property int index
            required property var modelData
            readonly property int bands: Math.max(1, deviceRow.modelData.colours.length)
            readonly property int band: Math.floor(deviceBands.width / bands)
            width: index === bands - 1 ? deviceBands.width - band * (bands - 1) : band
            height: deviceBands.height
            color: modelData
          }
        }
      }
      Text {
        anchors.centerIn: parent
        visible: deviceRow.modelData.colours.length === 0
        text: "–"
        color: themeRgb.dim
        font.family: themeRgb.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Column {
      id: deviceText
      anchors.left: deviceSwatch.right
      anchors.leftMargin: Style.space(10)
      anchors.right: choice.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: deviceRow.verticalCenter
      Text {
        width: parent.width
        text: deviceRow.modelData.name
        elide: Text.ElideRight
        color: themeRgb.foreground
        font.family: themeRgb.fontFamily
        font.pixelSize: Style.font.body
      }
      Text {
        width: parent.width
        text: Routing.detailText(deviceRow.modelData)
        elide: Text.ElideRight
        color: themeRgb.dim
        font.family: themeRgb.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Dropdown {
      id: choice
      anchors.right: deviceRow.right
      anchors.verticalCenter: deviceRow.verticalCenter
      width: Style.space(150)
      showLabel: false
      options: Routing.choiceOptions(deviceRow.modelData.source, deviceRow.count, deviceRow.modelData.choice)
      value: Routing.choiceValue(deviceRow.modelData, deviceRow.count)
      foreground: themeRgb.foreground
      fontFamily: themeRgb.fontFamily
      onChanged: function(v) {
        if (themeRgb.service) themeRgb.service.setAssign(Routing.assignKey(deviceRow.modelData), Routing.storedChoice(v))
      }
      // While the list is open it has the keys; closing hands them back.
      property bool counted: false
      onPopupOpenChanged: {
        if (popupOpen && !counted) { counted = true; themeRgb.openDropdowns++ }
        else if (!popupOpen && counted) {
          counted = false
          themeRgb.openDropdowns--
          if (themeRgb.opened) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
        }
      }
      Component.onDestruction: if (counted) themeRgb.openDropdowns--
    }
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
    hoveredLayout = ""
    lookupService()
    if (service) { service.refreshVariables(); service.refreshStops(); service.refreshHass() }
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
    // Wide enough for the mode chips in one row at any font size; the
    // Row's laid-out width is what the chips actually take.
    contentWidth: panel.fittedContentWidth(Math.max(Style.space(440), modeGroup.width))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(900))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The open menu takes every key, Esc included, so Esc closes the menu
      // before it closes the panel and j/k walk the list, not the chips.
      blocked: themeRgb.menuOpen || themeRgb.openDropdowns > 0

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
          spacing: Style.space(14)
          visible: themeRgb.openrgbPresent

        // Theme colours: how many, and their numbers ------------------------
        Column {
          width: parent.width
          spacing: Style.space(8)

          Item {
            width: parent.width
            height: Math.max(coloursHeader.implicitHeight, modeGroup.height)

            PanelSectionHeader {
              id: coloursHeader
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "THEME COLOURS"
              foreground: themeRgb.foreground
              fontFamily: themeRgb.fontFamily
            }

            Text {
              anchors.right: modeGroup.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: "How many"
              color: themeRgb.dim
              font.family: themeRgb.fontFamily
              font.pixelSize: Style.font.caption
            }

            ButtonGroup {
              id: modeGroup
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              options: themeRgb.modes
              value: themeRgb.modeValue
              foreground: themeRgb.foreground
              fontFamily: themeRgb.fontFamily
              focusable: false
              cursorIndex: themeRgb.cursorActive && themeRgb.cursorRow === "mode" ? themeRgb.cursorIndex : -1
              onChanged: function(v) { themeRgb.chooseMode(v) }
              // The pointer drives the same cursor the keys move; leaving the chip
              // it sits on clears it, so nothing stays lit behind the pointer.
              onHovered: function(index, isHovered) {
                if (!isHovered) {
                  if (themeRgb.cursorRow === "mode" && themeRgb.cursorIndex === index) themeRgb.cursorActive = false
                  return
                }
                themeRgb.cursorActive = true
                themeRgb.cursorRow = "mode"
                themeRgb.cursorIndex = index
              }
            }
          }

          // The numbers every device below refers to.
          Row {
            id: swatchRow
            width: parent.width
            spacing: Style.space(4)
            readonly property int count: Math.max(1, themeRgb.stops.length)
            readonly property real cell: (width - spacing * (count - 1)) / count
            Repeater {
              model: themeRgb.stops
              delegate: Rectangle {
                id: swatch
                required property int index
                required property var modelData
                width: swatchRow.cell
                height: Style.space(30)
                color: modelData
                border.width: 1
                border.color: Qt.rgba(themeRgb.foreground.r, themeRgb.foreground.g, themeRgb.foreground.b, 0.25)
                readonly property real luma: 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
                Text {
                  anchors.centerIn: parent
                  text: swatch.index + 1
                  color: swatch.luma > 0.5 ? "#000000" : "#ffffff"
                  font.family: themeRgb.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
              }
            }
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            visible: themeRgb.mode !== "custom"
            text: themeRgb.stops.length > 1
              ? "Colour 1 is the theme's accent; the rest follow the wallpaper. Below, each device says which of these numbers it shows."
              : "The theme's accent. Below, each device says whether it shows it."
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

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            visible: themeRgb.hassRows.length > 0
            text: "Computer lighting only. Home Assistant lights keep the brightness they are at."
            color: themeRgb.dim
            font.family: themeRgb.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        PanelSeparator { width: parent.width; foreground: themeRgb.foreground }

        // Where each colour goes ------------------------------------------
        Column {
          id: devicesColumn
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "WHERE EACH COLOUR GOES"
            foreground: themeRgb.foreground
            fontFamily: themeRgb.fontFamily
          }

          Text {
            text: "COMPUTER · OPENRGB"
            color: themeRgb.dim
            font.family: themeRgb.fontFamily
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: themeRgb.openrgbRows
            delegate: DeviceRow { width: devicesColumn.width }
          }

          Text {
            visible: themeRgb.openrgbRows.length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            text: themeRgb.syncing ? "Looking for devices…" : "OpenRGB found no devices on the last sync."
            color: themeRgb.dim
            font.family: themeRgb.fontFamily
            font.pixelSize: Style.font.caption
          }

          // A skipped device is why something is not lit.
          Repeater {
            model: themeRgb.skippedDetectors
            delegate: Item {
              id: skippedRow
              required property string modelData
              width: devicesColumn.width
              height: Math.max(skippedText.implicitHeight, retryButton.implicitHeight) + Style.space(4)

              Text {
                id: skippedText
                anchors.left: skippedRow.left
                anchors.right: retryButton.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: skippedRow.verticalCenter
                wrapMode: Text.WordWrap
                text: skippedRow.modelData + " is not lit: it stopped answering while devices were being found, so it is skipped."
                color: themeRgb.dim
                font.family: themeRgb.fontFamily
                font.pixelSize: Style.font.caption
              }

              Button {
                id: retryButton
                anchors.right: skippedRow.right
                anchors.verticalCenter: skippedRow.verticalCenter
                text: "Try again"
                bordered: true
                foreground: themeRgb.foreground
                fontFamily: themeRgb.fontFamily
                fontSize: Style.font.caption
                enabled: !!themeRgb.service
                Accessible.name: "Try " + skippedRow.modelData + " again"
                onClicked: themeRgb.service.retryDetector(skippedRow.modelData)
              }
            }
          }

          Item { width: 1; height: Style.space(2) }

          Text {
            text: "HOME ASSISTANT"
            color: themeRgb.dim
            font.family: themeRgb.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            visible: themeRgb.hassMessage !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: themeRgb.hassMessage
            color: themeRgb.dim
            font.family: themeRgb.fontFamily
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: themeRgb.hassRows
            delegate: DeviceRow { width: devicesColumn.width }
          }

          Text {
            visible: themeRgb.hassRows.length > 0
            width: parent.width
            wrapMode: Text.WordWrap
            text: "A light shows one colour. Theme RGB never turns a light on: one that is off takes its colour within about 20 seconds of being turned on."
            color: themeRgb.dim
            font.family: themeRgb.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        PanelSeparator { width: parent.width; foreground: themeRgb.foreground }

        // Keyboard pattern: how "All colours" is laid out -------------------
        Column {
          width: parent.width
          spacing: Style.space(8)
          opacity: themeRgb.patternInUse ? 1.0 : 0.5

          Item {
            width: parent.width
            height: patternHeader.implicitHeight

            PanelSectionHeader {
              id: patternHeader
              anchors.left: parent.left
              text: "PATTERN FOR ALL COLOURS"
              foreground: themeRgb.foreground
              fontFamily: themeRgb.fontFamily
            }
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: themeRgb.patternInUse
              ? "How a device set to all colours lays them out."
              : "No device is set to all colours, so the pattern is not used now."
            color: themeRgb.dim
            font.family: themeRgb.fontFamily
            font.pixelSize: Style.font.caption
          }

          Flow {
            id: layoutGroup
            width: parent.width
            spacing: Style.spacing.md
            Repeater {
              id: layoutButtons
              model: themeRgb.layouts
              delegate: Button {
                required property var modelData
                required property int index
                text: modelData.label
                selected: themeRgb.layout === modelData.value
                bordered: true
                foreground: themeRgb.foreground
                fontFamily: themeRgb.fontFamily
                hasCursor: themeRgb.cursorActive && themeRgb.cursorRow === "layout" && themeRgb.cursorIndex === index
                onClicked: themeRgb.chooseLayout(modelData.value)
                onHasCursorChanged: if (hasCursor) themeRgb.hoveredLayout = modelData.value
                onHovered: function(h) {
                  if (h) {
                    themeRgb.cursorActive = true
                    themeRgb.cursorRow = "layout"
                    themeRgb.cursorIndex = index
                    themeRgb.hoveredLayout = modelData.value
                  } else {
                    if (themeRgb.hoveredLayout === modelData.value) themeRgb.hoveredLayout = ""
                    if (themeRgb.cursorRow === "layout" && themeRgb.cursorIndex === index) themeRgb.cursorActive = false
                  }
                }
              }
            }
          }

          // The pattern under the pointer, else the chosen one, in words.
          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: themeRgb.shownLayout.label + (themeRgb.shownLayout.value === themeRgb.layout ? " (chosen)" : "") + ": " + themeRgb.shownLayout.tooltip
            color: themeRgb.foreground
            font.family: themeRgb.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            text: themeRgb.service && themeRgb.service.keyboardDetected
              ? "YOUR KEYBOARD, AS IT IS LIT"
              : "A STANDARD KEYBOARD (YOURS WAS NOT FOUND)"
            textFormat: Text.PlainText
            color: themeRgb.dim
            font.family: themeRgb.fontFamily
            font.pixelSize: Style.font.caption
          }
          Item {
            id: keyboardReference
            width: parent.width
            height: Math.max(1, themeRgb.keyboardRows.length) * Style.space(14)
            readonly property real unit: width / themeRgb.keyboardBounds.width
            Repeater {
              model: themeRgb.service ? themeRgb.service.keyboardPreview : []
              delegate: Rectangle {
                required property var modelData
                x: ((modelData.name === "Space" ? 4.5 : modelData.column) - themeRgb.keyboardBounds.left) * keyboardReference.unit
                y: themeRgb.keyboardRows.indexOf(modelData.row) * Style.space(14)
                width: Math.max(1, keyboardReference.unit * (modelData.name === "Space" ? 5.75 : 1) - Style.space(2))
                height: Style.space(11)
                color: modelData.color
              }
            }
          }
        }
        }
      }
      }
    }
  }
}
