pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui

// The bar's job is one glyph and one click: open the Theme RGB window
// (App.qml) through the shell. Everything shown comes from the shared
// service, which runs whether or not the window is open.
BarWidget {
  id: themeRgb

  moduleName: "huacnlee.theme_rgb"

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null

  // `barForeground` belongs to qs.Ui.Panel, not to BarWidget; the bar itself
  // is the source.
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool openrgbPresent: !!service && service.openrgbPresent
  readonly property bool windowOpen: !!service && service.windowOpen
  readonly property bool syncing: !!service && service.syncing

  readonly property string tooltip: {
    if (!service) return "Theme RGB"
    if (!openrgbPresent) return "Theme RGB · OpenRGB is not installed"
    if (syncing) return "Theme RGB · Syncing…"
    if (service.lastSyncFailed) return "Theme RGB · Last sync failed"
    return "Theme RGB · Your theme, on every light."
  }

  function openWindow() {
    if (!bar || !bar.shell) return
    if (typeof bar.shell.toggle === "function") bar.shell.toggle(moduleName, "{}")
    else if (typeof bar.shell.summon === "function") bar.shell.summon(moduleName, "{}")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: themeRgb.bar
    tooltipText: themeRgb.tooltip

    readonly property color glyphColor: themeRgb.openrgbPresent
      ? themeRgb.foreground
      : Qt.darker(themeRgb.foreground, 1.55)

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

    // Left opens the window; middle syncs now without opening anything.
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) themeRgb.openWindow()
      else if (buttonCode === Qt.MiddleButton && themeRgb.service && !themeRgb.syncing) themeRgb.service.apply()
    }
  }

  // The shell draws this accent line under its own open popouts; the window
  // is routed separately, so the widget mirrors that mark itself.
  Rectangle {
    readonly property bool vertical: !!themeRgb.bar && themeRgb.bar.vertical
    visible: themeRgb.windowOpen
    color: Color.accent
    width: vertical ? Style.space(2) : parent.width
    height: vertical ? parent.height : Style.space(2)
    anchors.bottom: vertical ? undefined : parent.bottom
    anchors.right: vertical ? parent.right : undefined
  }
}
