const fs = require("fs")
const vm = require("vm")

if (!fs.existsSync("Startup.js")) {
  console.error("not ok - first config load must refresh the preview and apply the saved settings")
  process.exit(1)
}

const source = fs.readFileSync("Startup.js", "utf8")
const context = {}
vm.runInNewContext(source, context, { filename: "Startup.js" })

if (typeof context.configLoaded !== "function") {
  console.error("not ok - first config load must refresh the preview and apply the saved settings")
  process.exit(1)
}

const calls = []
const service = {
  loadConfig(raw) { calls.push(["loadConfig", raw]) },
  refreshStops() { calls.push(["refreshStops"]) },
  apply() { calls.push(["apply"]) }
}

context.configLoaded(service, '{"brightness":55}')

const expected = JSON.stringify([
  ["loadConfig", '{"brightness":55}'],
  ["refreshStops"],
  ["apply"]
])

if (JSON.stringify(calls) !== expected) {
  console.error("not ok - first config load must refresh the preview and apply the saved settings")
  console.error(JSON.stringify(calls))
  process.exit(1)
}

console.log("ok - first config load refreshes the preview and applies the saved settings")

// The SDK port opens as soon as the server starts, and detection then
// registers devices over several seconds with long quiet gaps (DRAM over I2C
// first, keyboards and mice over HID later), so no reading of the list proves
// it is complete. Every change to a non-empty count is a reason to sync.
const cases = [
  [-1, 0, false],   // nothing yet
  [0, 0, false],    // still scanning
  [-1, 2, true],    // first devices: sync them now
  [0, 2, true],     // DRAM just appeared
  [2, 2, false],    // nothing new
  [2, 6, true],     // keyboard and mouse arrived
  [6, 5, true],     // a device went away
  [6, 0, false]     // server lost; nothing to light
]
if (typeof context.deviceCountChanged !== "function") {
  console.error("not ok - every new device count triggers a sync")
  process.exit(1)
}
for (const [prev, count, want] of cases) {
  if (context.deviceCountChanged(prev, count) !== want) {
    console.error(`not ok - every new device count triggers a sync (${prev} -> ${count})`)
    process.exit(1)
  }
}
console.log("ok - every new device count triggers a sync")

// Exercise the actual QML methods: panel changes must retain the case-lighting
// preference when they save the rest of the settings.
const qml = fs.readFileSync("Service.qml", "utf8")
const loadMethod = qml.match(/  function loadConfig\(raw\) \{[\s\S]*?(?=\n  \/\/ The panel's setters)/)
const saveMethod = qml.match(/  function save\(\) \{[\s\S]*?(?=\n  \/\/ The stops probe)/)
if (!loadMethod || !saveMethod) throw new Error("QML config methods were not found")
const configContext = {
  root: { configPath: "/unused-theme-rgb-test.json" },
  saveProcess: { running: false },
  allDevices: false
}
vm.runInNewContext(loadMethod[0] + "\n" + saveMethod[0], configContext)
configContext.loadConfig('{"mode":"palette","colors":8,"all_devices":true}')
configContext.colors = 3
configContext.save()
const saved = JSON.parse(configContext.saveProcess.command.at(-1))
if (saved.all_devices !== true || saved.colors !== 3) {
  throw new Error("Panel save lost the all-devices preference")
}
configContext.loadConfig('{}')
if (configContext.allDevices !== false) throw new Error("Old config should retain the original default")
console.log("ok - panel saves retain the all-devices preference")

// A detector skipped after a stall stays skipped across saves and restarts,
// so the panel can still name it and offer to try it again.
configContext.loadConfig('{"skipped_detectors":["SteelSeries Rival 710", 3, ""]}')
if (JSON.stringify(configContext.skippedDetectors) !== '["SteelSeries Rival 710"]') {
  throw new Error("Config load kept a malformed skipped detector")
}
configContext.brightness = 40
configContext.saveProcess.running = false
configContext.save()
const savedSkips = JSON.parse(configContext.saveProcess.command.at(-1))
if (JSON.stringify(savedSkips.skipped_detectors) !== '["SteelSeries Rival 710"]') {
  throw new Error("Panel save lost the skipped detectors")
}
configContext.loadConfig('{}')
if (configContext.skippedDetectors.length !== 0) throw new Error("Old config should skip nothing")
console.log("ok - skipped detectors survive a save")

// OpenRGB's server, run with -vv, names each detector before it runs it and
// prints "Detection completed" at the end. A detector that never returns (a
// SteelSeries Rival 710 that does not answer its firmware query blocks in
// hid_read forever) leaves its own line as the last word, and every device
// queued after it is never found. These lines are verbatim from OpenRGB 1.1.
const lines = [
  ["[4507      ][Debug  ][DetectionManager] SteelSeries Rival 710 is enabled", { kind: "detector", name: "SteelSeries Rival 710" }],
  ["[5004      ][Debug  ][DetectionManager] HYTE Mousemat is enabled", { kind: "detector", name: "HYTE Mousemat" }],
  ["[4552      ][Info   ][DetectionManager] Registering RGB controller SteelSeries QCK Prism Cloth XL", { kind: "progress" }],
  ["[5011      ][Trace  ][DetectionManager] HYTE Mousemat detection end", { kind: "progress" }],
  ["[5031      ][Info   ]|                Detection completed                 |", { kind: "completed" }],
  ["[4497      ][Info   ]|               Detecting I2C PCI devices            |", { kind: "progress" }],
  ["[170       ][Verbose][Crucial DRAM] Detection failed testing register A3.  Expected 03, got 00.", { kind: "progress" }],
  // The SDK server and the resource manager log every client connection,
  // and the panel polls the server once a second; that chatter is not
  // detection progress and must not hide a stall.
  ["[12086     ][Error  ][NetworkServer] recv_select failed receiving magic, closing listener", null],
  ["[12055     ][Info   ][NetworkServer] Network server started", null],
  ["[4507      ][Trace  ][ResourceManager] ResourceManager update signalled: 1", null],
  ["    OpenRGB v1.1", null],
  ["", null]
]
if (typeof context.detectionEvent !== "function") {
  console.error("not ok - server log lines are read as detection progress")
  process.exit(1)
}
for (const [line, want] of lines) {
  const got = context.detectionEvent(line)
  if (JSON.stringify(got) !== JSON.stringify(want)) {
    console.error(`not ok - server log lines are read as detection progress (${JSON.stringify(line)} -> ${JSON.stringify(got)})`)
    process.exit(1)
  }
}
console.log("ok - server log lines are read as detection progress")

// Detection stalls when a detector was named and nothing has been logged for
// the quiet limit. The longest gap in a healthy run is about a second (DRAM
// probing over I2C), so the limit leaves a wide margin.
const stalls = [
  [{ detector: "SteelSeries Rival 710", lastLine: 0, completed: false }, 9999, ""],
  [{ detector: "SteelSeries Rival 710", lastLine: 0, completed: false }, 10000, "SteelSeries Rival 710"],
  [{ detector: "SteelSeries Rival 710", lastLine: 0, completed: true }, 60000, ""],
  [{ detector: "", lastLine: 0, completed: false }, 60000, ""]
]
if (typeof context.stalledDetector !== "function") {
  console.error("not ok - a detector that stops logging is named as stalled")
  process.exit(1)
}
for (const [state, now, want] of stalls) {
  if (context.stalledDetector(state, now, 10000) !== want) {
    console.error(`not ok - a detector that stops logging is named as stalled (${JSON.stringify(state)} at ${now})`)
    process.exit(1)
  }
}
console.log("ok - a detector that stops logging is named as stalled")
