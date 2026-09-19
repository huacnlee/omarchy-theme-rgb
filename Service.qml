import QtQuick
import Quickshell
import Quickshell.Io

// Keeps OpenRGB devices in the theme's colours. The colour maths and device
// handling live in bin/omarchy-theme-rgb-apply so they can be tested (and
// reused as a plain theme-set hook) without a running shell; this service
// decides *when* to run it, keeps a headless OpenRGB server alive so each run
// takes a second rather than fifteen, and holds the state the bar panel shows.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/omarchy/theme-rgb.json"
  readonly property string devicesPath: home + "/.local/state/omarchy/theme-rgb/devices"
  readonly property string applyScript: localPath(Qt.resolvedUrl("bin/omarchy-theme-rgb-apply"))

  // What theme-rgb.json says, with the script's defaults.
  property string mode: "palette"        // "single" | "palette" | "custom"
  property string single: ""             // "" = keyboard.rgb, else accent
  property string anchor: "accent"
  property int colors: 5
  property var custom: []
  property int brightness: 100

  // [{ name, hex }] the current theme defines, for the swatches.
  property var variables: []
  // "#rrggbb" colours the script will light, for the preview.
  property var stops: []
  // [{ id, name, leds, type }] found on the last apply, desk peripherals first.
  property var devices: []

  property bool openrgbPresent: false
  property bool serverRunning: false
  // True once an SDK server answers on its port (ours or the user's), or once
  // we have given up waiting. Until then applies queue: a direct probe while
  // the server is still enumerating sees only the devices it has not grabbed.
  property bool serverReady: false
  property bool syncing: false
  property bool applyPending: false
  property string lastSyncedAt: ""
  property bool lastSyncFailed: false

  function localPath(url) {
    var s = String(url)
    return s.indexOf("file://") === 0 ? decodeURIComponent(s.substring(7)) : s
  }

  function isVariable(name) {
    for (var i = 0; i < variables.length; i++)
      if (variables[i].name === name) return true
    return false
  }

  function loadConfig(raw) {
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) { parsed = null }
    if (!parsed || typeof parsed !== "object") parsed = {}
    mode = parsed.mode === "single" || parsed.mode === "custom" ? parsed.mode : "palette"
    single = typeof parsed.single === "string" ? parsed.single : ""
    anchor = typeof parsed.anchor === "string" && parsed.anchor !== "" ? parsed.anchor : "accent"
    var n = Number(parsed.colors)
    colors = n === 2 || n === 3 ? n : 5
    custom = Array.isArray(parsed.custom) ? parsed.custom.map(function(v) { return String(v) }) : []
    var b = Number(parsed.brightness)
    brightness = isFinite(b) && b >= 10 && b <= 100 ? Math.round(b) : 100
  }

  // The panel's setters. Each writes the whole file, then re-syncs.
  function setMode(value) { if (value === "single" || value === "palette" || value === "custom") { mode = value; save() } }
  function setSingle(name) { single = name; save() }
  function setAnchor(name) { anchor = name; save() }
  function setColors(n) { if (n === 2 || n === 3 || n === 5) { colors = n; save() } }
  function toggleCustom(name) {
    var next = custom.filter(function(v) { return v !== name })
    if (next.length === custom.length) next.push(name)
    custom = next
    save()
  }
  function setBrightness(value) {
    var b = Math.round(Number(value))
    if (!isFinite(b)) return
    brightness = Math.max(10, Math.min(100, b))
    save()
  }

  // Written through a plain process (not FileView.setText) so the write is a
  // simple truncate-and-write the config watch below sees as a modification,
  // and so a save never races the reload of our own file.
  function save() {
    var payload = {
      mode: mode,
      single: single,
      anchor: anchor,
      colors: colors,
      custom: custom,
      brightness: brightness
    }
    saveProcess.command = ["bash", "-c",
      'mkdir -p "$(dirname "$1")" && printf "%s\\n" "$2" > "$1"', "_",
      root.configPath, JSON.stringify(payload, null, 2)]
    saveProcess.running = true
    refreshStops()
    apply()
  }

  function refreshStops() {
    if (stopsProbe.running) stopsProbe.running = false
    stopsProbe.running = true
  }

  function refreshVariables() {
    if (variablesProbe.running) variablesProbe.running = false
    variablesProbe.running = true
  }

  // Coalesce: a change that lands while a run is in flight queues one more
  // run, so rapid switching never fires concurrent OpenRGB calls and the
  // last state always wins.
  function apply() {
    if (applyProcess.running || !serverReady) {
      root.applyPending = true
      return
    }
    root.syncing = true
    applyProcess.running = true
  }

  function markServerReady() {
    serverReady = true
    readinessTimer.stop()
    if (applyPending) {
      applyPending = false
      apply()
    }
  }

  function onThemeChanged() {
    refreshVariables()
    refreshStops()
    apply()
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadConfig(text())
    onLoadFailed: root.loadConfig("")
    // An edit from outside the shell (an editor, a script) takes effect like
    // one from the panel; our own saves land here too and just re-read what
    // we already hold.
    onFileChanged: reload()
  }

  FileView {
    id: devicesFile
    path: root.devicesPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      var lines = String(text() || "").split("\n")
      var next = []
      for (var i = 0; i < lines.length; i++) {
        var parts = lines[i].split("|")
        if (parts.length < 3) continue
        next.push({ id: parts[0], name: parts[1], leds: Number(parts[2]) || 0, type: parts[3] || "" })
      }
      root.devices = next
    }
    onLoadFailed: root.devices = []
    onFileChanged: reload()
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
    onExited: function(exitCode) {
      root.openrgbPresent = exitCode === 0
      if (root.openrgbPresent) {
        root.startServer()
        readinessTimer.start()
      } else {
        root.markServerReady()
      }
    }
  }

  // Poll the SDK port once a second for up to 20 s, then go ahead regardless.
  property int readinessPolls: 0

  Timer {
    id: readinessTimer
    interval: 1000
    repeat: true
    onTriggered: {
      root.readinessPolls++
      if (root.readinessPolls > 20) { root.markServerReady(); return }
      if (!portProbe.running) portProbe.running = true
    }
  }

  Process {
    id: portProbe
    command: ["bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/6742"]
    onExited: function(exitCode) { if (exitCode === 0) root.markServerReady() }
  }

  // Without a server every `openrgb` call re-probes the hardware (seconds per
  // call). Keep a headless SDK server for the life of the shell; the CLI
  // autoconnects to it. If the user already runs one the bind fails and we
  // quietly use theirs; if ours dies we try again after a pause, not in a
  // tight loop.
  property int serverStarts: 0

  function startServer() {
    if (serverProcess.running || serverStarts >= 5) return
    serverStarts++
    serverProcess.running = true
  }

  Process {
    id: serverProcess
    command: ["openrgb", "--server", "--noautoconnect"]
    stderr: StdioCollector {
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg !== "") console.warn("huacnlee.theme_rgb: openrgb server: " + msg.split("\n").slice(-3).join(" | "))
      }
    }
    onStarted: root.serverRunning = true
    onExited: function(exitCode) {
      root.serverRunning = false
      console.warn("huacnlee.theme_rgb: openrgb server exited with " + exitCode + " (start " + root.serverStarts + ")")
      serverRetryTimer.restart()
    }
  }

  Timer {
    id: serverRetryTimer
    interval: 30000
    repeat: false
    onTriggered: root.startServer()
  }

  Process {
    id: saveProcess
    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("huacnlee.theme_rgb: could not write " + root.configPath)
    }
  }

  Process {
    id: variablesProbe
    command: ["bash", root.applyScript, "variables"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        var next = []
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].trim().split(/\s+/)
          if (parts.length === 2 && /^[0-9a-f]{6}$/.test(parts[1]))
            next.push({ name: parts[0], hex: "#" + parts[1] })
        }
        root.variables = next
      }
    }
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
      devicesFile.reload()
      if (root.applyPending) {
        root.applyPending = false
        root.apply()
      }
    }
  }

  // Match the theme at shell start (login) and whenever the plugin is enabled.
  Component.onCompleted: {
    openrgbProbe.running = true
    refreshVariables()
    refreshStops()
    apply()
  }
}
