import QtQuick
import Quickshell
import Quickshell.Io

// Keeps OpenRGB devices in the theme's colours. The colour maths and device
// handling live in bin/omarchy-theme-rgb-apply so they can be tested (and
// reused as a plain theme-set hook) without a running shell; this service
// decides *when* to run it and holds the state the bar panel shows.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/omarchy/theme-rgb.json"
  readonly property string applyScript: localPath(Qt.resolvedUrl("bin/omarchy-theme-rgb-apply"))

  // "single" | "2" | "3" | "5" — what theme-rgb.json says, default 5 colours.
  property string choice: "5"
  // Brightened hex colours the script will light, for the panel preview.
  property var stops: []
  property bool openrgbPresent: false
  property bool syncing: false
  property bool applyPending: false
  property string lastSyncedAt: ""
  property bool lastSyncFailed: false

  function localPath(url) {
    var s = String(url)
    return s.indexOf("file://") === 0 ? decodeURIComponent(s.substring(7)) : s
  }

  function choiceFromConfig(raw) {
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) { parsed = null }
    if (!parsed || typeof parsed !== "object") return "5"
    if (parsed.mode === "single") return "single"
    var n = Number(parsed.colors)
    return n === 2 || n === 3 || n === 5 ? String(n) : "5"
  }

  // The panel calls this. Writing the file is what changes the setting; the
  // apply is explicit rather than left to the file watch, which an atomic
  // rename can slip past.
  function setChoice(value) {
    var next = String(value)
    if (next !== "single" && next !== "2" && next !== "3" && next !== "5") return
    root.choice = next
    var payload = next === "single" ? { mode: "single" } : { mode: "palette", colors: Number(next) }
    configFile.setText(JSON.stringify(payload, null, 2) + "\n")
    refreshStops()
    apply()
  }

  function refreshStops() {
    if (stopsProbe.running) { stopsProbe.running = false }
    stopsProbe.running = true
  }

  // Coalesce: a change that lands while a run is in flight queues one more
  // run, so rapid switching never fires concurrent OpenRGB calls and the
  // last state always wins.
  function apply() {
    if (applyProcess.running) {
      root.applyPending = true
      return
    }
    root.syncing = true
    applyProcess.running = true
  }

  function onThemeChanged() {
    refreshStops()
    apply()
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.choice = root.choiceFromConfig(text())
    onLoadFailed: root.choice = "5"
    // An edit from outside the shell (an editor, a script) should take effect
    // like one from the panel.
    onFileChanged: {
      reload()
      root.refreshStops()
      root.apply()
    }
  }

  // omarchy-theme-set writes theme.name only after the new theme directory
  // has replaced current/theme, so by the time this fires keyboard.rgb and
  // colors.toml already belong to the new theme.
  FileView {
    path: root.home + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: root.onThemeChanged()
  }

  Process {
    id: openrgbProbe
    command: ["bash", "-c", "command -v openrgb"]
    onExited: function(exitCode) { root.openrgbPresent = exitCode === 0 }
  }

  Process {
    id: stopsProbe
    command: ["bash", root.applyScript, "stops"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        var next = []
        for (var i = 0; i < lines.length; i++) {
          var hex = lines[i].trim()
          if (/^[0-9a-fA-F]{6}$/.test(hex)) next.push("#" + hex.toLowerCase())
        }
        root.stops = next
      }
    }
  }

  Process {
    id: applyProcess
    command: ["bash", root.applyScript]
    onExited: function(exitCode) {
      root.syncing = false
      root.lastSyncFailed = exitCode !== 0
      if (exitCode !== 0) console.warn("huacnlee.theme_rgb: apply exited with " + exitCode)
      else root.lastSyncedAt = Qt.formatTime(new Date(), "HH:mm")
      if (root.applyPending) {
        root.applyPending = false
        root.apply()
      }
    }
  }

  // Match the theme at shell start (login) and whenever the plugin is enabled.
  Component.onCompleted: {
    openrgbProbe.running = true
    refreshStops()
    apply()
  }
}
