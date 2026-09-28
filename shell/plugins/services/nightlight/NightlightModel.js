// Temperatures below the identity point count as night light. Keep in sync
// with bin/roseshell-toggle-nightlight, which applies the same threshold.
var IDENTITY_TEMPERATURE = 6000
var DEFAULT_TEMPERATURE = 4000
var MIN_TEMPERATURE = 2500
var MAX_TEMPERATURE = 5500

function temperatureFromOutput(output) {
  var match = String(output === undefined || output === null ? "" : output).match(/[0-9]+/)
  return match ? Number(match[0]) : null
}

function isNightlight(temperature) {
  return temperature !== null && temperature !== undefined && temperature < IDENTITY_TEMPERATURE
}

function clampTemperature(value) {
  var n = Math.round(Number(value))
  if (!isFinite(n) || n <= 0) return DEFAULT_TEMPERATURE
  return Math.max(MIN_TEMPERATURE, Math.min(MAX_TEMPERATURE, n))
}

function normalizeTime(value, fallback) {
  var m = String(value || "").match(/^(\d{1,2}):(\d{2})$/)
  if (!m || Number(m[1]) > 23 || Number(m[2]) > 59) return fallback
  return (m[1].length === 1 ? "0" : "") + m[1] + ":" + m[2]
}

function timeToMinutes(value) {
  var parts = String(value).split(":")
  return Number(parts[0]) * 60 + Number(parts[1])
}

function minutesToTime(minutes) {
  var m = ((Math.round(minutes) % 1440) + 1440) % 1440
  var h = Math.floor(m / 60)
  var mm = m % 60
  return (h < 10 ? "0" : "") + h + ":" + (mm < 10 ? "0" : "") + mm
}

// True when `now` falls in [start, end), wrapping past midnight when end <= start.
function inWindow(now, start, end) {
  if (start === end) return false
  return start < end ? (now >= start && now < end) : (now >= start || now < end)
}

// zone1970.tab coordinates: ±DDMM±DDDMM or ±DDMMSS±DDDMMSS.
function parseIsoCoordinates(text) {
  var m = String(text || "").match(/^([+-])(\d{2})(\d{2})(\d{2})?([+-])(\d{3})(\d{2})(\d{2})?$/)
  if (!m) return null
  var lat = Number(m[2]) + Number(m[3]) / 60 + Number(m[4] || 0) / 3600
  var lon = Number(m[6]) + Number(m[7]) / 60 + Number(m[8] || 0) / 3600
  return { latitude: m[1] === "-" ? -lat : lat, longitude: m[5] === "-" ? -lon : lon }
}

// Sunrise and sunset for `date` in minutes after local midnight (the NOAA
// almanac approximation, good to a minute or two). Polar day or night gives
// a window that is always on or always off.
function sunTimes(date, latitude, longitude) {
  var rad = Math.PI / 180
  var start = new Date(date.getFullYear(), 0, 0)
  var dayOfYear = Math.floor((date - start) / 86400000)
  var lngHour = longitude / 15
  var offsetHours = -date.getTimezoneOffset() / 60

  function event(rising) {
    var t = dayOfYear + ((rising ? 6 : 18) - lngHour) / 24
    var M = 0.9856 * t - 3.289
    var L = M + 1.916 * Math.sin(M * rad) + 0.020 * Math.sin(2 * M * rad) + 282.634
    L = ((L % 360) + 360) % 360
    var RA = Math.atan(0.91764 * Math.tan(L * rad)) / rad
    RA = ((RA % 360) + 360) % 360
    RA += Math.floor(L / 90) * 90 - Math.floor(RA / 90) * 90
    RA /= 15
    var sinDec = 0.39782 * Math.sin(L * rad)
    var cosDec = Math.cos(Math.asin(sinDec))
    var cosH = (Math.cos(90.833 * rad) - sinDec * Math.sin(latitude * rad)) / (cosDec * Math.cos(latitude * rad))
    if (cosH > 1) return rising ? null : "never" // sun stays down
    if (cosH < -1) return rising ? "never" : null // sun stays up
    var H = rising ? 360 - Math.acos(cosH) / rad : Math.acos(cosH) / rad
    H /= 15
    var T = H + RA - 0.06571 * t - 6.622
    var local = T - lngHour + offsetHours
    return ((local % 24) + 24) % 24 * 60
  }

  var sunrise = event(true)
  var sunset = event(false)
  if (typeof sunrise !== "number" || typeof sunset !== "number") {
    // Polar night (no sunrise): a sunset-to-sunrise window spanning the whole
    // day. Polar day: an empty window.
    return sunrise === null ? { sunrise: 1440, sunset: 0 } : { sunrise: 0, sunset: 0 }
  }
  return { sunrise: Math.round(sunrise), sunset: Math.round(sunset) }
}

if (typeof module !== "undefined") {
  module.exports = {
    IDENTITY_TEMPERATURE: IDENTITY_TEMPERATURE,
    temperatureFromOutput: temperatureFromOutput,
    isNightlight: isNightlight,
    clampTemperature: clampTemperature,
    normalizeTime: normalizeTime,
    timeToMinutes: timeToMinutes,
    minutesToTime: minutesToTime,
    inWindow: inWindow,
    parseIsoCoordinates: parseIsoCoordinates,
    sunTimes: sunTimes
  }
}
