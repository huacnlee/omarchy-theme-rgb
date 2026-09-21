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
