import QtQuick
import Quickshell
import Quickshell.Io
import "Startup.js" as Startup

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
  readonly property string detectorScript: localPath(Qt.resolvedUrl("bin/omarchy-theme-rgb-detector"))
  readonly property string hassScript: localPath(Qt.resolvedUrl("bin/omarchy-theme-rgb-hass"))
  readonly property string stateDir: home + "/.local/state/omarchy/theme-rgb"

  // What theme-rgb.json says, with the script's defaults.
  property string mode: "palette"        // "single" | "palette" | "custom"
  property string single: ""             // "" = accent
  property int colors: 8
  property var custom: []
  property int brightness: 100
  property string layout: "omarchy"     // spatial layouts or named key-accent presets
  property bool allDevices: false
  // OpenRGB detectors this plugin turned off because detection stalled in
  // them, so the panel can name them and offer to try again.
  property var skippedDetectors: []
  // What each device lights, keyed "openrgb:<name>" or "hass:<entity>":
  // "all", a colour number, or "off". See device_choice in the script.
  property var assign: ({})
  // "home_assistant" as the file has it, written back untouched.
  property var homeAssistant: null

  // [{ name, hex }] the current theme defines, for the swatches.
  property var variables: []
  // "#rrggbb" colours the script will light, per device class, for the
  // preview. `stops` is the desk list, which is also what a device of an
  // unknown type gets.
  property var keyboardPreview: []
  property bool keyboardDetected: false
  property var deskStops: []
  property var ambientStops: []
  readonly property var stops: deskStops
  // The same colours before brightness: what Home Assistant lights get.
  property var rawStops: []
  // What every known device lights, from the script's `plan` (see Routing.js).
  property string planText: ""
  // How the last Home Assistant read or write went: ok, no-address,
  // no-token, unauthorized, unreachable or error ("" before the first).
  property string hassStatus: ""
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
    var n = Number(parsed.colors)
    colors = n === 3 || n === 5 ? n : 8
    custom = Array.isArray(parsed.custom) ? parsed.custom.map(function(v) { return String(v) }) : []
    var b = Number(parsed.brightness)
    brightness = isFinite(b) && b >= 10 && b <= 100 ? Math.round(b) : 100
    var l = String(parsed.layout || "")
    if (l === "wasd") l = "gaming"
    if (l === "vim") l = "lazyvim"
    if (l === "function" || l === "arrows") l = "zones"
    layout = ["flow", "rows", "columns", "zones", "gaming", "outline", "lazyvim", "omarchy"].indexOf(l) >= 0 ? l : "omarchy"
    allDevices = parsed.all_devices === true
    skippedDetectors = Array.isArray(parsed.skipped_detectors)
      ? parsed.skipped_detectors.filter(function(v) { return typeof v === "string" && v !== "" })
      : []
    var a = {}
    if (parsed.assign && typeof parsed.assign === "object" && !Array.isArray(parsed.assign)) {
      for (var k in parsed.assign) {
        var v = parsed.assign[k]
        if (v === "all" || v === "off" || (typeof v === "number" && v >= 1 && v <= 99 && Math.floor(v) === v)) a[k] = v
      }
    }
    assign = a
    homeAssistant = parsed.home_assistant && typeof parsed.home_assistant === "object" ? parsed.home_assistant : null
  }

  // The panel's setters. Each writes the whole file, then re-syncs.
  function setMode(value) { if (value === "single" || value === "palette" || value === "custom") { mode = value; save() } }
  function setSingle(name) { single = name; save() }
  function setColors(n) { if (n === 3 || n === 5 || n === 8) { colors = n; save() } }
  // One save for "palette with n colours", so the file never holds a half
  // state between two writes.
  function setPalette(n) { if (n === 3 || n === 5 || n === 8) { colors = n; mode = "palette"; save() } }
  function setLayout(value) {
    if (["flow", "rows", "columns", "zones", "gaming", "outline", "lazyvim", "omarchy"].indexOf(value) >= 0) { layout = value; save() }
  }
  function toggleCustom(name) {
    var next = custom.filter(function(v) { return v !== name })
    if (next.length === custom.length) next.push(name)
    custom = next
    save()
  }

  // One device's choice; the plan is redrawn once the file is written.
  function setAssign(key, value) {
    if (!key || !(value === "all" || value === "off" || (typeof value === "number" && value >= 1))) return
    var next = {}
    for (var k in assign) next[k] = assign[k]
    next[key] = value
    assign = next
    save()
  }

  function setBrightness(value) {
    var b = Math.round(Number(value))
    if (!isFinite(b)) return
    brightness = Math.max(10, Math.min(100, b))
    save()
  }

  // Written through a plain process (not FileView.setText) so the write is a
  // simple truncate-and-write the config watch below sees as a modification.
  // Saves are serialised: a save requested while one is in flight runs once
  // more when it finishes, with whatever the state is by then, so quick
  // successive changes always end with the file holding the latest state.
  // The preview and the hardware are refreshed only after the write landed,
  // because the script reads the file.
  property bool savePending: false
  readonly property bool saving: saveProcess.running || savePending

  function save() {
    if (saveProcess.running) {
      savePending = true
      return
    }
    var payload = {
      mode: mode,
      single: single,
      colors: colors,
      custom: custom,
      brightness: brightness,
      layout: layout,
      all_devices: allDevices,
      skipped_detectors: skippedDetectors,
      assign: assign
    }
    if (homeAssistant) payload.home_assistant = homeAssistant
    saveProcess.command = ["bash", "-c",
      'mkdir -p "$(dirname "$1")" && printf "%s\\n" "$2" > "$1"', "_",
      root.configPath, JSON.stringify(payload, null, 2)]
    saveProcess.running = true
  }

  // The stops probe is never killed mid-run: a refresh during a run queues
  // one more run, so the preview always ends on the current state.
  property bool stopsPending: false

  function refreshStops() {
    if (stopsProbe.running) {
      stopsPending = true
      return
    }
    stopsProbe.running = true
    if (keyboardProbe.running) keyboardProbe.running = false
    keyboardProbe.running = true
    refreshPlan()
  }

  function refreshPlan() {
    if (planProbe.running) planProbe.running = false
    planProbe.running = true
  }

  // Asks Home Assistant for its lights again (the panel does on opening);
  // the list lands in hass-lights, which redraws the plan.
  function refreshHass() {
    if (!hassProbe.running) hassProbe.running = true
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

  // Re-runs the presence probe; the probe itself starts the server and the
  // first sync when openrgb has appeared since it last looked.
  function recheckOpenrgb() {
    if (openrgbProbe.running) return
    openrgbProbe.running = true
  }

  // Installs the package where the user can watch it: a floating terminal
  // running omarchy-pkg-add, the same helper Omarchy's own update flow uses,
  // so the password prompt and the package output land in front of them
  // rather than in the shell's log. The launcher detaches the terminal, so nothing
  // here can wait for it to close; the watch below re-probes every few
  // seconds until openrgb turns up, and gives up after ten minutes.
  function installOpenrgb() {
    if (openrgbPresent) return
    Quickshell.execDetached(["bash", "-lc",
      "exec omarchy-launch-floating-terminal-with-presentation omarchy-pkg-add openrgb"])
    installWatchPolls = 0
    installWatch.restart()
  }

  property int installWatchPolls: 0

  Timer {
    id: installWatch
    interval: 3000
    repeat: true
    onTriggered: {
      root.installWatchPolls++
      if (root.openrgbPresent || root.installWatchPolls > 200) { installWatch.stop(); return }
      root.recheckOpenrgb()
    }
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    // Our own writes land here too. While a save is in flight or queued the
    // file lags the state, so do not let a stale read overwrite what the
    // user just chose.
    onLoaded: if (!root.saving) Startup.configLoaded(root, text())
    onLoadFailed: if (!root.saving) Startup.configLoaded(root, "")
    // An edit from outside the shell (an editor, a script) takes effect like
    // one from the panel.
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
      root.refreshPlan()
    }
    onLoadFailed: root.devices = []
    onFileChanged: reload()
  }

  // A light that is off is not coloured (a sync never turns a lamp on), so
  // one that has just been turned on is coloured then. While any light has
  // a colour, Home Assistant is asked every 20 s which lights are on.
  property var hassOn: ({})

  readonly property bool hassAssigned: {
    for (var k in assign) if (k.indexOf("hass:") === 0 && assign[k] !== "off") return true
    return false
  }

  FileView {
    id: hassLightsFile
    path: root.stateDir + "/hass-lights"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var on = {}, turnedOn = false
      var lines = String(text() || "").split("\n")
      for (var i = 0; i < lines.length; i++) {
        var f = lines[i].split("\t")
        if (f.length < 3 || f[2] !== "on") continue
        on[f[0]] = true
        var choice = root.assign["hass:" + f[0]]
        if (root.hassOn[f[0]] !== true && choice !== undefined && choice !== "off") turnedOn = true
      }
      var first = root.hassSeen === false
      root.hassSeen = true
      root.hassOn = on
      root.refreshPlan()
      // The first reading only records what is on; the startup sync covers it.
      if (turnedOn && !first && !applyProcess.running && !hassApply.running) hassApply.running = true
    }
    onFileChanged: reload()
  }
  property bool hassSeen: false

  Timer {
    interval: 20000
    repeat: true
    running: root.hassAssigned
    onTriggered: root.refreshHass()
  }

  Process {
    id: hassApply
    command: ["bash", root.applyScript, "hass"]
  }

  FileView {
    id: hassStatusFile
    path: root.stateDir + "/hass-status"
    watchChanges: true
    printErrors: false
    onLoaded: root.hassStatus = String(text() || "").trim()
    onLoadFailed: root.hassStatus = ""
    onFileChanged: reload()
  }

  Process {
    id: hassProbe
    command: ["bash", root.hassScript, "lights"]
    // The list and the status arrive through their files.
    onExited: { hassStatusFile.reload(); root.refreshPlan() }
  }

  Process {
    id: planProbe
    command: ["bash", root.applyScript, "plan"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.planText = String(text || "")
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

  // The order of the colours follows the wallpaper, and the wallpaper can
  // change without the theme (omarchy-theme-bg-next swaps the symlink). A
  // symlink swap is invisible to a file watch on the image, so poll the link
  // target every few seconds; resolving a symlink costs nothing.
  property string backgroundTarget: ""

  Timer {
    interval: 5000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!backgroundProbe.running) backgroundProbe.running = true
  }

  Process {
    id: backgroundProbe
    command: ["readlink", "-f", root.home + "/.local/state/omarchy/current/background"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var target = String(text || "").trim()
        if (target === root.backgroundTarget) return
        var first = root.backgroundTarget === ""
        root.backgroundTarget = target
        // The first reading just records what is there; the startup sync
        // already used it.
        if (!first) { root.refreshStops(); root.apply() }
      }
    }
  }

  Process {
    id: openrgbProbe
    command: ["bash", "-c", "command -v openrgb"]
    onExited: function(exitCode) {
      var present = exitCode === 0
      var appeared = present && !root.openrgbPresent
      root.openrgbPresent = present
      if (!present) {
        root.markServerReady()
        return
      }
      root.startServer()
      root.readinessPolls = 0
      root.lastDeviceCount = -1
      readinessTimer.start()
      // Freshly installed: hold the first sync until the server answers,
      // exactly as at shell start, rather than probing hardware it is still
      // enumerating.
      if (appeared) {
        root.serverReady = false
        root.apply()
      }
    }
  }

  // Watch the server's device list once a second for its first minute.
  // The port answers as soon as the server starts, but detection runs for
  // seconds more with quiet gaps: DRAM over I2C first, keyboards and mice
  // over HID later. Syncing on the open port alone lit only the RAM at login
  // and left the keyboard in its power-on colours. So the first non-empty
  // list releases the queued sync, and every later change to it syncs again.
  // With nothing listed after 20 s, go ahead regardless. The port is checked
  // first so the CLI never falls back to probing the hardware itself.
  property int readinessPolls: 0
  property int lastDeviceCount: -1

  Timer {
    id: readinessTimer
    interval: 1000
    repeat: true
    onTriggered: {
      root.readinessPolls++
      if (root.readinessPolls > 60) { readinessTimer.stop(); return }
      if (root.readinessPolls > 20 && !root.serverReady) root.markServerReady()
      if (!deviceCountProbe.running) deviceCountProbe.running = true
    }
  }

  Process {
    id: deviceCountProbe
    command: ["bash", "-c",
      "exec 3<>/dev/tcp/127.0.0.1/6742 || exit 1; exec 3>&-; "
      + "timeout 10 openrgb --list-devices 2>/dev/null | grep -cE '^[0-9]+: '"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var count = parseInt(String(text || "").trim(), 10)
        if (!isFinite(count)) return
        var changed = Startup.deviceCountChanged(root.lastDeviceCount, count)
        root.lastDeviceCount = count
        if (!changed) return
        if (root.serverReady) root.apply()
        else root.markServerReady()
      }
    }
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

  // A device that never answers OpenRGB's probe blocks detection for good:
  // the detector waits on it without a timeout, and every device queued
  // behind it is never found (a SteelSeries Rival 710 left only the RAM lit).
  // The server runs with -vv so its log names each detector before running
  // it. When detection goes quiet inside one, that detector is turned off in
  // OpenRGB's settings and the server is started again without it. The panel
  // lists what was skipped and can try it again.
  //
  // At most two detectors are skipped on its own per session: a stall the
  // log cannot pin on a detector would otherwise blame one detector after
  // another, each one switched off in OpenRGB's settings.
  readonly property int maxAutoSkips: 2
  property int autoSkips: 0
  readonly property int stallQuietMs: 10000
  property var detection: ({ detector: "", lastLine: 0, completed: false })
  property bool restartPending: false
  property string detectorAction: ""
  property string detectorName: ""

  function onServerLine(line) {
    var event = Startup.detectionEvent(line)
    if (!event || detection.completed) return
    detection.lastLine = Date.now()
    if (event.kind === "detector") detection.detector = event.name
    else if (event.kind === "completed") {
      detection.completed = true
      stallWatch.stop()
    }
  }

  function skipDetector(name) {
    stallWatch.stop()
    if (autoSkips >= maxAutoSkips) {
      console.warn("huacnlee.theme_rgb: OpenRGB detection stalled in '" + name + "'; " + maxAutoSkips + " detectors were skipped already, leaving it")
      return
    }
    autoSkips++
    console.warn("huacnlee.theme_rgb: OpenRGB detection stalled in '" + name + "'; skipping it")
    if (skippedDetectors.indexOf(name) < 0) {
      skippedDetectors = skippedDetectors.concat([name])
      save()
    }
    setDetector("disable", name)
  }

  function retryDetector(name) {
    if (detectorProcess.running) return
    // Asked for by hand, so it may be skipped again if it stalls again.
    autoSkips = Math.max(0, autoSkips - 1)
    skippedDetectors = skippedDetectors.filter(function(v) { return v !== name })
    save()
    setDetector("enable", name)
  }

  // The flag is written while the old server is still up, and the server is
  // replaced once the write has landed, so the new one reads it at start.
  function setDetector(action, name) {
    if (detectorProcess.running) return
    stallWatch.stop()
    serverReady = false
    detectorAction = action
    detectorName = name
    detectorProcess.command = ["bash", root.detectorScript, action, name]
    detectorProcess.running = true
  }

  // Applies wait for the new server (setDetector already holds them): a CLI
  // call with no server to talk to would probe the hardware itself,
  // alongside the starting server.
  function restartServer() {
    serverReady = false
    if (serverProcess.running) {
      restartPending = true
      // SIGKILL: a server stuck in a blocking read does not act on SIGTERM.
      serverProcess.signal(9)
      return
    }
    serverStarts = 0
    startServer()
    readinessPolls = 0
    lastDeviceCount = -1
    readinessTimer.restart()
    apply()
  }

  Process {
    id: detectorProcess
    // When the flag could not be written (OpenRGB.json is not JSON, jq is
    // missing), a restart would only stall the same way again: the list
    // goes back to what OpenRGB has, and syncs carry on with the server as
    // it is.
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.restartServer()
        return
      }
      console.warn("huacnlee.theme_rgb: could not " + root.detectorAction + " the OpenRGB detector '" + root.detectorName + "'")
      var name = root.detectorName
      var others = root.skippedDetectors.filter(function(v) { return v !== name })
      root.skippedDetectors = root.detectorAction === "disable" ? others : others.concat([name])
      root.save()
      root.serverReady = true
      root.apply()
    }
  }

  Timer {
    id: stallWatch
    interval: 1000
    repeat: true
    onTriggered: {
      var name = Startup.stalledDetector(root.detection, Date.now(), root.stallQuietMs)
      if (name !== "") root.skipDetector(name)
    }
  }

  Process {
    id: serverProcess
    command: ["openrgb", "--server", "--noautoconnect", "-vv"]
    stdout: SplitParser {
      onRead: function(line) { root.onServerLine(line) }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg !== "") console.warn("huacnlee.theme_rgb: openrgb server: " + msg.split("\n").slice(-3).join(" | "))
      }
    }
    onStarted: {
      root.serverRunning = true
      root.detection = { detector: "", lastLine: Date.now(), completed: false }
      stallWatch.restart()
    }
    onExited: function(exitCode) {
      root.serverRunning = false
      stallWatch.stop()
      if (root.restartPending) {
        root.restartPending = false
        root.restartServer()
        return
      }
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
      if (root.savePending) {
        root.savePending = false
        root.save()
        return
      }
      root.refreshStops()
      root.apply()
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
    id: keyboardProbe
    command: ["bash", root.applyScript, "preview"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var keys = [], detected = false
        var lines = String(text || "").trim().split("\n")
        for (var i = 0; i < lines.length; i++) {
          var f = lines[i].split("\t")
          if (f.length !== 7 || !/^[0-9a-f]{6}$/.test(f[2])) continue
          var row = Number(f[0]), column = Number(f[1])
          if (!isFinite(row) || !isFinite(column) || row < 0 || row > 5 || column < 0 || column > 22) continue
          var slot = Number(f[4])
          if (!isFinite(slot) || slot < 0 || slot > 31 || Math.floor(slot) !== slot) continue
          detected = f[5] === "detected"
          keys.push({ row: row, column: column, color: "#" + f[2], name: f[3] })
        }
        root.keyboardPreview = keys
        root.keyboardDetected = detected
      }
    }
  }

  Process {
    id: stopsProbe
    command: ["bash", root.applyScript, "stops"]
    stdout: StdioCollector {
      waitForEnd: true
      // "desk a,b,c", "ambient a,b,c" and "raw a,b,c".
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        var found = { desk: [], ambient: [], raw: [] }
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].trim().split(/\s+/)
          if (parts.length !== 2 || !(parts[0] in found)) continue
          found[parts[0]] = parts[1].split(",").filter(function(h) { return /^[0-9a-fA-F]{6}$/.test(h) })
            .map(function(h) { return "#" + h.toLowerCase() })
        }
        root.deskStops = found.desk
        root.ambientStops = found.ambient
        root.rawStops = found.raw
      }
    }
    onExited: function() {
      if (root.stopsPending) {
        root.stopsPending = false
        root.refreshStops()
      }
    }
  }

  // A failed apply (openrgb exited non-zero or timed out, see
  // ~/.local/state/omarchy/theme-rgb/last-apply.log) gets one retry after a
  // pause: a device re-enumerating or a busy SDK server is usually over by
  // then. A second failure stays reported until something changes.
  property bool applyRetried: false

  Timer {
    id: applyRetryTimer
    interval: 3000
    repeat: false
    onTriggered: root.apply()
  }

  Process {
    id: applyProcess
    command: ["bash", root.applyScript]
    onExited: function(exitCode) {
      root.syncing = false
      root.lastSyncFailed = exitCode !== 0
      devicesFile.reload()
      if (root.applyPending) {
        root.applyPending = false
        root.applyRetried = false
        root.apply()
        return
      }
      if (exitCode !== 0) {
        console.warn("huacnlee.theme_rgb: apply exited with " + exitCode + (root.applyRetried ? "" : ", retrying"))
        if (!root.applyRetried) {
          root.applyRetried = true
          applyRetryTimer.restart()
        }
        return
      }
      root.applyRetried = false
      root.refreshStops()
    }
  }

  // Match the theme at shell start (login) and whenever the plugin is enabled.
  Component.onCompleted: {
    openrgbProbe.running = true
    refreshVariables()
    refreshStops()
    refreshHass()
    apply()
  }
}
