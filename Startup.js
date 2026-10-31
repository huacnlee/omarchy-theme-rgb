function configLoaded(service, raw) {
  service.loadConfig(raw)
  service.refreshStops()
  service.apply()
}

// OpenRGB opens its SDK port before detection has finished, and detection
// registers devices over several seconds with quiet gaps between them (DRAM
// over I2C first, keyboards and mice over HID later), so no single reading
// shows the list is complete. Sync whenever the list grows or shrinks.
function deviceCountChanged(previousCount, count) {
  return count > 0 && count !== previousCount
}

// Reads one line of the OpenRGB server's -vv output. The detection manager
// names each detector before running it ("<name> is enabled"); everything
// else logged while detecting is progress, and "Detection completed" ends the
// run. Not progress: anything that is not a log line (the version banner),
// and the network server's and resource manager's lines, which client
// connections keep producing while a detector is stuck.
function detectionEvent(line) {
  var s = String(line || "")
  if (!/^\[\s*\d+\s*\]\[/.test(s)) return null
  if (/\]\[(NetworkServer|ResourceManager)\]/.test(s)) return null
  if (/\|\s*Detection completed\s*\|/.test(s)) return { kind: "completed" }
  var m = s.match(/\]\[DetectionManager\] (.+) is enabled\s*$/)
  if (m) return { kind: "detector", name: m[1] }
  return { kind: "progress" }
}

// The detector a stalled run is stuck in, or "". A run is stalled when a
// detector was named, detection has not completed, and nothing has been
// logged for quietMs.
function stalledDetector(state, now, quietMs) {
  if (!state || state.completed || !state.detector) return ""
  return now - state.lastLine >= quietMs ? state.detector : ""
}
