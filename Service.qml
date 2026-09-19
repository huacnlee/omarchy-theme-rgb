import QtQuick
import Quickshell
import Quickshell.Io

// Retints OpenRGB devices whenever the Omarchy theme changes. The colour maths
// and device handling live in bin/omarchy-openrgb-apply so they can be tested
// (and reused as a plain theme-set hook) without a running shell; this file
// only decides *when* to run it.
Item {
  id: root

  // Injected by omarchy-shell (unused, declared so the loader stays quiet).
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string applyScript: localPath(Qt.resolvedUrl("bin/omarchy-openrgb-apply"))

  property bool applyPending: false

  function localPath(url) {
    var s = String(url)
    return s.indexOf("file://") === 0 ? decodeURIComponent(s.substring(7)) : s
  }

  // Coalesce: a theme change that lands while a run is in flight queues one
  // more run, so rapid switching never fires concurrent OpenRGB calls and the
  // last theme always wins.
  function apply() {
    if (applyProcess.running) {
      root.applyPending = true
      return
    }
    applyProcess.running = true
  }

  // omarchy-theme-set writes theme.name only after the new theme directory
  // has replaced current/theme, so by the time this fires keyboard.rgb and
  // colors.toml already belong to the new theme.
  FileView {
    path: root.home + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: root.apply()
  }

  Process {
    id: applyProcess
    command: ["bash", root.applyScript]
    onExited: function(exitCode) {
      if (exitCode !== 0)
        console.warn("huacnlee.openrgb: apply exited with " + exitCode)
      if (root.applyPending) {
        root.applyPending = false
        root.apply()
      }
    }
  }

  // Match the theme at shell start (login) and whenever the plugin is enabled.
  Component.onCompleted: root.apply()
}
