pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui

// Bar button plus a small settings popout for Theme RGB. All state lives in
// Service.qml (looked up through the shell); this file only shows it and
// forwards the user's choice. The preview strip is painted from the same
// `stops` the script sends to the hardware, so what you see is what lights.
Panel {
  id: themeRgb
  moduleName: "huacnlee.theme_rgb"
  ipcTarget: "huacnlee.theme_rgb"
  // The bar registers the IPC handler for placed widgets; a second one here
  // would only log that it is unused.
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)

  property var service: null
  property int cursorIndex: -1
  property bool cursorActive: false

  readonly property var choices: [
    { value: "single", label: "Single", tooltip: "One theme colour on every device" },
    { value: "2", label: "2 colours", tooltip: "Accent plus its nearest theme colour" },
    { value: "3", label: "3 colours", tooltip: "Accent plus the two nearest theme colours" },
    { value: "5", label: "5 colours", tooltip: "Accent plus the four nearest theme colours" }
  ]

  readonly property string choice: service ? String(service.choice) : "5"
  readonly property var stops: service && service.stops ? service.stops : []
  readonly property bool openrgbPresent: service ? service.openrgbPresent : false
  readonly property bool syncing: service ? service.syncing : false

  readonly property string metaText: choice === "single" ? "One theme colour" : choice + " theme colours"
  readonly property string detailText: {
    if (!service) return "Service not running"
    if (!openrgbPresent) return "OpenRGB is not installed"
    if (syncing) return "Syncing…"
    if (service.lastSyncFailed) return "Last sync failed"
    if (service.lastSyncedAt !== "") return "Synced " + service.lastSyncedAt
    return "Not synced yet"
  }

  function lookupService() {
    if (!bar || !bar.shell || typeof bar.shell.serviceFor !== "function") return
    var found = bar.shell.serviceFor(moduleName)
    if (found) service = found
  }

  function choose(value) {
    if (service) service.setChoice(value)
  }

  function chooseAt(index) {
    if (index >= 0 && index < choices.length) choose(choices[index].value)
  }

  function syncNow() {
    if (service && !syncing) service.apply()
  }

  function selectedIndex() {
    for (var i = 0; i < choices.length; i++)
      if (choices[i].value === choice) return i
    return 0
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
    if (service) service.refreshStops()
    cursorActive = false
    cursorIndex = selectedIndex()
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
    // Wide enough for the four choice chips in one row at any font size.
    contentWidth: panel.fittedContentWidth(Math.max(Style.space(340), choiceGroup.implicitWidth))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(400))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (!themeRgb.cursorActive) { themeRgb.cursorActive = true; return }
        if (dx === 0) return
        var next = themeRgb.cursorIndex + dx
        if (next < 0) next = themeRgb.choices.length - 1
        if (next >= themeRgb.choices.length) next = 0
        themeRgb.cursorIndex = next
      }
      onActivateRequested: if (themeRgb.cursorActive) themeRgb.chooseAt(themeRgb.cursorIndex)
      onCloseRequested: themeRgb.close()
      onTabRequested: function(direction) { themeRgb.switchPanel(direction) }
      onTextKey: function(text) {
        var key = String(text || "").toLowerCase()
        if (key >= "1" && key <= "4") themeRgb.chooseAt(Number(key) - 1)
        else if (key === "r") themeRgb.syncNow()
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          id: hero
          width: parent.width
          title: "Theme RGB"
          meta: themeRgb.metaText
          detail: themeRgb.detailText
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

        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "COLOURS"
            foreground: themeRgb.foreground
            fontFamily: themeRgb.fontFamily
          }

          ButtonGroup {
            id: choiceGroup
            options: themeRgb.choices
            value: themeRgb.choice
            foreground: themeRgb.foreground
            fontFamily: themeRgb.fontFamily
            focusable: false
            cursorIndex: themeRgb.cursorActive ? themeRgb.cursorIndex : -1
            onChanged: function(v) { themeRgb.choose(v) }
            onHovered: function(index, isHovered) {
              if (!isHovered) return
              themeRgb.cursorActive = true
              themeRgb.cursorIndex = index
            }
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: themeRgb.choice === "single"
              ? "The theme's keyboard colour, or its accent."
              : "The accent and the theme colours nearest to it, blended across each device's LEDs."
            color: themeRgb.dim
            font.family: themeRgb.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // Preview: a linear gradient through the stops, the way a strip of
        // LEDs would show it. One stop paints a solid bar.
        Rectangle {
          id: preview
          width: parent.width
          height: Style.space(18)
          color: "transparent"
          border.width: 1
          border.color: Qt.rgba(themeRgb.foreground.r, themeRgb.foreground.g, themeRgb.foreground.b, 0.40)

          Canvas {
            id: previewCanvas
            anchors.fill: parent
            anchors.margins: 1
            onPaint: {
              var ctx = getContext("2d")
              ctx.clearRect(0, 0, width, height)
              var colors = themeRgb.stops
              if (!colors || colors.length === 0) return
              if (colors.length === 1) {
                ctx.fillStyle = colors[0]
              } else {
                var grad = ctx.createLinearGradient(0, 0, width, 0)
                for (var i = 0; i < colors.length; i++)
                  grad.addColorStop(i / (colors.length - 1), colors[i])
                ctx.fillStyle = grad
              }
              ctx.fillRect(0, 0, width, height)
            }
            Connections {
              target: themeRgb
              function onStopsChanged() { previewCanvas.requestPaint() }
            }
            onWidthChanged: requestPaint()
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
      }
    }
  }
}
