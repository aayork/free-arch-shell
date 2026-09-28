import QtQuick
import Quickshell.Io
import "NightlightModel.js" as NightlightModel

Item {
  id: root

  // Injected by roseshell-shell (the first-party service loader).
  property var shell: null

  // shell.json "nightlight": { temperature, schedule, start, end }.
  //   schedule: "manual" (default), "custom" (start..end, local "HH:MM"), or
  //   "sunset" (sunset..sunrise at the timezone's coordinates).
  // bin/roseshell-toggle-nightlight reads the same temperature for callers
  // outside the shell (keybindings, menu, ssh).
  readonly property var config: shell && shell.shellConfig && typeof shell.shellConfig.nightlight === "object"
    && shell.shellConfig.nightlight ? shell.shellConfig.nightlight : ({})
  readonly property int nightTemperature: NightlightModel.clampTemperature(config.temperature)
  readonly property int dayTemperature: 6500
  readonly property string schedule: ["custom", "sunset"].indexOf(config.schedule) !== -1 ? config.schedule : "manual"
  readonly property string startTime: NightlightModel.normalizeTime(config.start, "20:00")
  readonly property string endTime: NightlightModel.normalizeTime(config.end, "07:00")

  property bool stateLoaded: false
  property var temperature: null
  readonly property bool enabled: stateLoaded && NightlightModel.isNightlight(temperature)

  property bool hasPendingTemperature: false
  property int pendingTemperature: 0

  // Location for the sunset schedule, from the system timezone's entry in
  // zone1970.tab (the zone's principal city). Close enough for sun times, and
  // needs no network or location permission.
  property string zone: ""
  property real latitude: NaN
  property real longitude: NaN
  property var sunTimes: null // { sunrise, sunset } in minutes after local midnight

  // The schedule's last verdict. A transition applies it; in between, a manual
  // toggle holds until the next transition, the way GNOME's night light works.
  property var lastScheduled: null

  function refresh() {
    if (!statusProbe.running) statusProbe.running = true
  }

  function setNightlight(value) {
    applyTemperature(value ? nightTemperature : dayTemperature)
  }

  function toggle() {
    setNightlight(!enabled)
  }

  function applyTemperature(temp) {
    root.temperature = temp
    root.stateLoaded = true

    if (applyProcess.running) {
      root.pendingTemperature = temp
      root.hasPendingTemperature = true
      return
    }

    runApply(temp)
  }

  function runApply(temp) {
    // uwsm-app requires a full UWSM-managed session (real Roseshell installs
    // one); this fork runs plain Hyprland, so fall back to bare hyprsunset
    // when it's absent instead of silently no-op'ing on every toggle.
    applyProcess.command = ["bash", "-lc",
      "pgrep -x hyprsunset >/dev/null || { " +
      "if command -v uwsm-app >/dev/null 2>&1; then setsid uwsm-app -- hyprsunset >/dev/null 2>&1 & " +
      "else setsid hyprsunset >/dev/null 2>&1 & fi; sleep 1; }; " +
      "hyprctl hyprsunset temperature " + Number(temp)]
    applyProcess.running = true
  }

  function updateSunTimes() {
    root.sunTimes = isNaN(root.latitude) ? null
      : NightlightModel.sunTimes(new Date(), root.latitude, root.longitude)
  }

  // [start, end] in minutes after midnight for the active schedule, or null.
  function scheduleWindow() {
    if (root.schedule === "custom")
      return [NightlightModel.timeToMinutes(root.startTime), NightlightModel.timeToMinutes(root.endTime)]
    if (root.schedule === "sunset" && root.sunTimes)
      return [root.sunTimes.sunset, root.sunTimes.sunrise]
    return null
  }

  function evaluateSchedule() {
    var window = scheduleWindow()
    if (!window) { root.lastScheduled = null; return }
    var now = new Date()
    var scheduled = NightlightModel.inWindow(now.getHours() * 60 + now.getMinutes(), window[0], window[1])
    if (scheduled !== root.lastScheduled) {
      root.lastScheduled = scheduled
      if (scheduled !== root.enabled) root.setNightlight(scheduled)
    }
  }

  function restartSchedule() {
    root.lastScheduled = null
    evaluateSchedule()
  }

  onScheduleChanged: restartSchedule()
  onStartTimeChanged: restartSchedule()
  onEndTimeChanged: restartSchedule()
  onSunTimesChanged: if (root.schedule === "sunset") restartSchedule()

  // A new intensity takes effect at once while night light is on.
  onNightTemperatureChanged: if (root.enabled && root.temperature !== root.nightTemperature) root.applyTemperature(root.nightTemperature)

  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: {
      root.updateSunTimes()
      root.evaluateSchedule()
    }
  }

  Process {
    id: locationProbe
    command: ["bash", "-c",
      "tz=$(timedatectl show -p Timezone --value 2>/dev/null); "
      + "[ -n \"$tz\" ] || tz=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||'); "
      + "printf '%s\\t%s\\n' \"$tz\" \"$(awk -F'\\t' -v tz=\"$tz\" '$3 == tz { print $2; exit }' /usr/share/zoneinfo/zone1970.tab 2>/dev/null)\""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").trim().split("\t")
        root.zone = parts[0] || ""
        var coords = NightlightModel.parseIsoCoordinates(parts[1] || "")
        if (coords) {
          root.latitude = coords.latitude
          root.longitude = coords.longitude
        }
        root.updateSunTimes()
      }
    }
  }

  Process {
    id: statusProbe
    command: ["hyprctl", "hyprsunset", "temperature"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.temperature = NightlightModel.temperatureFromOutput(text)
        root.stateLoaded = true
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.temperature = null
        root.stateLoaded = true
      }
    }
  }

  Process {
    id: applyProcess
    onExited: function() {
      if (root.hasPendingTemperature) {
        root.hasPendingTemperature = false
        root.runApply(root.pendingTemperature)
        return
      }

      root.refresh()
    }
  }

  Component.onCompleted: {
    refresh()
    locationProbe.running = true
    evaluateSchedule()
  }

  IpcHandler {
    target: "nightlight"

    function status(): string {
      return JSON.stringify({
        enabled: root.enabled,
        temperature: root.temperature,
        nightTemperature: root.nightTemperature,
        schedule: root.schedule,
        start: root.startTime,
        end: root.endTime,
        zone: root.zone,
        sunrise: root.sunTimes ? NightlightModel.minutesToTime(root.sunTimes.sunrise) : null,
        sunset: root.sunTimes ? NightlightModel.minutesToTime(root.sunTimes.sunset) : null
      })
    }

    function refresh(): void {
      root.refresh()
    }

    // Applies a temperature without saving it: the settings slider previews
    // with this while dragging, then saves nightlight.temperature on release.
    function preview(temperature: string): string {
      var t = NightlightModel.clampTemperature(temperature)
      root.applyTemperature(t)
      return String(t)
    }

    function enable(): string {
      root.setNightlight(true)
      return "enabled"
    }

    function disable(): string {
      root.setNightlight(false)
      return "disabled"
    }

    function toggle(): string {
      var enabling = !root.enabled
      root.setNightlight(enabling)
      return enabling ? "enabled" : "disabled"
    }
  }
}
