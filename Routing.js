// Where each theme colour goes, as the panel shows it. The apply script's
// `plan` command decides what every device lights (one tab-separated line per
// device: source, key, name, detail, choice, colours); these helpers turn that
// into rows and into the choices a device's dropdown offers.
//
// A choice is "all" (every colour, placed by the keyboard pattern), a colour
// number ("1" is the first swatch), or "off" (left as it is). A Home Assistant
// light shows one colour at a time, so it is never offered "all".

function parsePlan(text) {
  var rows = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var f = lines[i].split("\t")
    if (f.length !== 6 || (f[0] !== "openrgb" && f[0] !== "hass") || f[1] === "") continue
    var colours = f[5].split(",").filter(function(h) { return /^[0-9a-fA-F]{6}$/.test(h) })
      .map(function(h) { return "#" + h.toLowerCase() })
    rows.push({ source: f[0], key: f[1], name: f[2], detail: f[3], choice: f[4], colours: colours })
  }
  return rows
}

// The settings key a device's choice is stored under.
function assignKey(row) {
  return row.source + ":" + row.key
}

// The colour number a choice past the palette lands on: colour 5 of three
// colours is colour 2.
function wrapped(n, count) {
  return count > 0 ? ((n - 1) % count) + 1 : n
}

function choiceOptions(source, count, current) {
  var options = []
  if (source === "openrgb" && count > 1)
    options.push({ value: "all", label: "All " + count + " colours" })
  for (var n = 1; n <= count; n++)
    options.push({ value: String(n), label: "Colour " + n })
  var c = Number(current)
  if (isFinite(c) && c > count && Math.floor(c) === c)
    options.push({ value: String(c), label: "Colour " + c + " (= " + wrapped(c, count) + ")" })
  options.push({ value: "off", label: source === "hass" ? "Not changed" : "Left as it is" })
  return options
}

// The dropdown's value for a row: with one colour, "all" is colour 1.
function choiceValue(row, count) {
  if (row.choice === "all" && count <= 1) return "1"
  return row.choice
}

// What to store for a picked value: numbers as numbers.
function storedChoice(value) {
  return value === "all" || value === "off" ? value : Number(value)
}

// The line under a device's name.
function detailText(row) {
  if (row.source === "hass") {
    if (row.detail === "on") return "On"
    if (row.detail === "off") return "Off · takes its colour when turned on"
    return row.detail === "unavailable" ? "Unavailable" : row.detail
  }
  return row.detail
}

// True when some device lights every colour, so the keyboard pattern matters.
function patternInUse(rows, count) {
  if (count <= 1) return false
  for (var i = 0; i < rows.length; i++)
    if (rows[i].source === "openrgb" && rows[i].choice === "all") return true
  return false
}

// What the Home Assistant section says instead of (or above) its lights.
function hassMessage(status, lightCount) {
  if (status === "no-address")
    return "Not set up. Theme RGB uses the address and token of the Home Assistant bar plugin, or \"home_assistant\" in theme-rgb.json."
  if (status === "no-token") return "No access token in the keyring for this Home Assistant."
  if (status === "unauthorized") return "Home Assistant refused the access token."
  if (status === "unreachable") return "Home Assistant did not answer."
  if (status === "error") return "Home Assistant could not be read or set; see last-hass.log."
  if (status === "ok" && lightCount === 0) return "No colour lights in Home Assistant."
  return ""
}
