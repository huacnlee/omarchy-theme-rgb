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
