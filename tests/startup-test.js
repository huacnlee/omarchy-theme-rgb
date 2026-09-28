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
