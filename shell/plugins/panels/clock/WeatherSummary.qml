import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import "../weather/Model.js" as WeatherModel

// Compact local weather for the clock popup: current conditions, today's
// high/low, and the next three days. Same sources as the weather plugin —
// Open-Meteo for the numbers, and wttr.in only to find where "here" is when
// no location is saved (roseshell-weather-location owns weather.json).
ColumnLayout {
  id: root

  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family
  // The popup is showing; a stale report refetches when it opens.
  property bool active: false

  readonly property int staleMs: 15 * 60 * 1000

  property var savedLocation: ({ name: "", latitude: null, longitude: null })
  // Filled from wttr's nearest_area when nothing is saved; kept for the
  // session so reopening the popup skips the slow lookup.
  property var detectedLocation: null
  property var forecast: null
  property double fetchedAt: 0
  property bool failed: false

  readonly property bool hasSavedCoordinates: savedLocation.latitude !== null && savedLocation.longitude !== null
  readonly property var place: hasSavedCoordinates ? savedLocation : detectedLocation
  readonly property string placeName: place ? place.name : ""
  readonly property var current: WeatherModel.openMeteoCurrentCondition(forecast)
  readonly property bool useImperial: WeatherModel.shouldUseImperial("", Qt.locale().name, place ? (place.country || "") : "")
  readonly property var upcoming: WeatherModel.openMeteoForecastDays(forecast, Qt.formatDate(new Date(), "yyyy-MM-dd"))
  readonly property var today: {
    var daily = forecast && forecast.daily ? forecast.daily : null
    if (!daily || !daily.time || daily.time.length === 0) return null
    return {
      maxC: daily.temperature_2m_max ? daily.temperature_2m_max[0] : null,
      minC: daily.temperature_2m_min ? daily.temperature_2m_min[0] : null
    }
  }

  function temp(celsius) {
    if (celsius === null || celsius === undefined || celsius === "") return ""
    var v = useImperial ? WeatherModel.celsiusToFahrenheit(celsius) : celsius
    return WeatherModel.roundedTemp(v) + "°"
  }

  function condition(code) {
    var c = parseInt(String(code), 10)
    if (c === 0) return "Clear"
    if (c === 1) return "Mostly clear"
    if (c === 2) return "Partly cloudy"
    if (c === 3) return "Overcast"
    if (c === 45 || c === 48) return "Fog"
    if (c >= 51 && c <= 57) return "Drizzle"
    if (c >= 61 && c <= 67) return "Rain"
    if (c >= 71 && c <= 77) return "Snow"
    if (c >= 80 && c <= 82) return "Showers"
    if (c === 85 || c === 86) return "Snow showers"
    if (c >= 95) return "Thunderstorms"
    return ""
  }

  function refreshIfStale() {
    if (Date.now() - fetchedAt > staleMs || failed) refresh()
  }

  function refresh() {
    failed = false
    if (place) fetchForecast(place.latitude, place.longitude)
    else if (!locateProc.running) locateProc.running = true
  }

  function fetchForecast(lat, lon) {
    if (forecastProc.running) return
    forecastProc.command = ["curl", "-fsS", "--max-time", "8",
      "https://api.open-meteo.com/v1/forecast"
      + "?latitude=" + encodeURIComponent(String(lat))
      + "&longitude=" + encodeURIComponent(String(lon))
      + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
      + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
      + "&forecast_days=4&timezone=auto"]
    forecastProc.running = true
  }

  onActiveChanged: if (active) refreshIfStale()
  onPlaceChanged: if (place && !forecastProc.running) refresh()

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/roseshell/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.savedLocation = WeatherModel.parseLocationFile(text())
    onLoadFailed: root.savedLocation = WeatherModel.parseLocationFile("")
  }

  Process {
    id: locateProc
    command: ["curl", "-fsS", "--max-time", "10", "https://wttr.in/?format=j1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var area = JSON.parse(String(text || "")).nearest_area[0]
          root.detectedLocation = {
            name: area.areaName[0].value,
            country: area.country && area.country[0] ? area.country[0].value : "",
            latitude: parseFloat(area.latitude),
            longitude: parseFloat(area.longitude)
          }
        } catch (e) {
          root.failed = true
        }
      }
    }
  }

  Process {
    id: forecastProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.forecast = JSON.parse(String(text || ""))
          root.fetchedAt = Date.now()
        } catch (e) {
          root.failed = true
        }
      }
    }
    onExited: function(exitCode) { if (exitCode !== 0) root.failed = true }
  }

  Timer {
    interval: root.staleMs
    repeat: true
    running: root.fetchedAt > 0
    onTriggered: root.refresh()
  }

  spacing: Style.space(10)

  RowLayout {
    Layout.fillWidth: true
    visible: !!root.current
    spacing: Style.space(12)

    Text {
      textFormat: Text.PlainText
      text: WeatherModel.currentIcon(root.current, "")
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.displayLarge
      Layout.alignment: Qt.AlignVCenter
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(1)

      Text {
        textFormat: Text.PlainText
        text: root.current ? root.temp(root.forecast.current.temperature_2m) : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
        font.bold: true
      }

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: {
          if (!root.current) return ""
          var parts = [root.condition(root.current.openMeteoWeatherCode)]
          parts.push("Feels " + root.temp(root.forecast.current.apparent_temperature))
          return parts.filter(function(p) { return p !== "" }).join(" · ")
        }
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    ColumnLayout {
      Layout.alignment: Qt.AlignVCenter
      spacing: Style.space(1)

      Text {
        textFormat: Text.PlainText
        Layout.alignment: Qt.AlignRight
        Layout.maximumWidth: Style.space(150)
        text: root.placeName
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        Layout.alignment: Qt.AlignRight
        visible: !!root.today
        text: root.today ? "H " + root.temp(root.today.maxC) + "  L " + root.temp(root.today.minC) : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Row {
    id: daysRow
    Layout.fillWidth: true
    visible: root.upcoming.length > 0

    Repeater {
      model: root.upcoming

      ColumnLayout {
        required property var modelData
        width: daysRow.width / Math.max(1, root.upcoming.length)
        spacing: Style.space(2)

        Text {
          textFormat: Text.PlainText
          Layout.alignment: Qt.AlignHCenter
          text: WeatherModel.dayName(modelData.date, function(d) { return Qt.formatDate(d, "ddd") })
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          textFormat: Text.PlainText
          Layout.alignment: Qt.AlignHCenter
          text: WeatherModel.dayIcon(modelData)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
        }

        Text {
          textFormat: Text.PlainText
          Layout.alignment: Qt.AlignHCenter
          text: WeatherModel.bareTempForDay(modelData, "max", root.useImperial) + " " + WeatherModel.bareTempForDay(modelData, "min", root.useImperial)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  Text {
    textFormat: Text.PlainText
    Layout.fillWidth: true
    visible: !root.current
    text: root.failed ? "Weather unavailable — click to retry" : "Loading weather…"
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    horizontalAlignment: Text.AlignHCenter

    TapHandler { enabled: root.failed; onTapped: root.refresh() }
  }
}
