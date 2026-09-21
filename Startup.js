function configLoaded(service, raw) {
  service.loadConfig(raw)
  service.refreshStops()
  service.apply()
}
