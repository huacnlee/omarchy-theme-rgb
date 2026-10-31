// What the panel makes of the script's plan: rows, the choices a device's
// dropdown offers, and the value it stores.
const fs = require("fs")
const vm = require("vm")
const assert = require("assert")

const context = {}
vm.runInNewContext(fs.readFileSync("Routing.js", "utf8"), context, { filename: "Routing.js" })
const R = context

let failures = 0
function check(name, fn) {
  try { fn(); console.log("ok - " + name) }
  catch (e) { failures++; console.log("not ok - " + name); console.log("  " + e.message) }
}
const plain = v => JSON.parse(JSON.stringify(v))

check("plan lines become rows; malformed lines are dropped", () => {
  const rows = R.parsePlan([
    "openrgb\tApex Pro\tApex Pro\tKeyboard\tall\tFF0000,00ff00",
    "hass\tlight.desk\tDesk lamp\toff\toff\t",
    "openrgb\tbroken line",
    "other\tx\tx\tx\tx\tff0000"
  ].join("\n"))
  assert.deepStrictEqual(plain(rows), [
    { source: "openrgb", key: "Apex Pro", name: "Apex Pro", detail: "Keyboard", choice: "all", colours: ["#ff0000", "#00ff00"] },
    { source: "hass", key: "light.desk", name: "Desk lamp", detail: "off", choice: "off", colours: [] }
  ])
  assert.strictEqual(R.assignKey(rows[1]), "hass:light.desk")
})

check("a computer device is offered all colours, each number, and off", () => {
  assert.deepStrictEqual(plain(R.choiceOptions("openrgb", 3, "all")).map(o => o.value), ["all", "1", "2", "3", "off"])
})

check("a Home Assistant light is never offered all colours", () => {
  assert.deepStrictEqual(plain(R.choiceOptions("hass", 3, "off")).map(o => o.value), ["1", "2", "3", "off"])
})

check("a stored number past the palette stays listed, saying where it lands", () => {
  const options = plain(R.choiceOptions("hass", 3, "5"))
  assert.deepStrictEqual(options[3], { value: "5", label: "Colour 5 (= 2)" })
})

check("with one colour, all colours shows as colour 1", () => {
  assert.strictEqual(R.choiceValue({ choice: "all" }, 1), "1")
  assert.deepStrictEqual(plain(R.choiceOptions("openrgb", 1, "all")).map(o => o.value), ["1", "off"])
})

check("picked values are stored as numbers or words", () => {
  assert.strictEqual(R.storedChoice("2"), 2)
  assert.strictEqual(R.storedChoice("all"), "all")
  assert.strictEqual(R.storedChoice("off"), "off")
})

check("the pattern matters only when a computer device lights every colour", () => {
  const rows = [{ source: "openrgb", choice: "1" }, { source: "hass", choice: "all" }]
  assert.strictEqual(R.patternInUse(rows, 3), false)
  assert.strictEqual(R.patternInUse([{ source: "openrgb", choice: "all" }], 3), true)
  assert.strictEqual(R.patternInUse([{ source: "openrgb", choice: "all" }], 1), false)
})

check("Home Assistant problems are said, a working one with lights says nothing", () => {
  assert.ok(R.hassMessage("no-token", 0).length > 0)
  assert.ok(R.hassMessage("ok", 0).length > 0)
  assert.strictEqual(R.hassMessage("ok", 2), "")
  assert.ok(R.hassMessage("no-keyring", 0).indexOf("libsecret") >= 0)
  assert.ok(R.hassMessage("bad-address", 0).length > 0)
})

check("re-picking what a row shows stores nothing, so a stored all survives one colour", () => {
  assert.strictEqual(R.samePick({ choice: "all" }, 1, "1"), true)
  assert.strictEqual(R.samePick({ choice: "all" }, 3, "1"), false)
  assert.strictEqual(R.samePick({ choice: "2" }, 3, "2"), true)
})

check("a lamp that is off and not set says only that it is off", () => {
  assert.strictEqual(R.detailText({ source: "hass", detail: "off", choice: "off" }), "Off")
  assert.ok(R.detailText({ source: "hass", detail: "off", choice: "2" }).indexOf("turned on") > 0)
})

check("the Home Assistant form shows until it answers", () => {
  assert.strictEqual(R.hassNeedsForm("ok"), false)
  assert.strictEqual(R.hassNeedsForm(""), false)
  assert.strictEqual(R.hassNeedsForm("no-address"), true)
  assert.strictEqual(R.hassNeedsForm("unauthorized"), true)
  assert.strictEqual(R.hostOf("https://ha.example.com:8123/"), "ha.example.com:8123")
})

process.exit(failures ? 1 : 0)
