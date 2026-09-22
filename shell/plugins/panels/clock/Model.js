// Pure date/format math for the clock widget and its world-clock panel.
// Everything here is locale- and Qt-free so it can be unit tested under node
// (test/shell.d/clock-test.sh); the QML owns month/weekday naming and any
// Qt.formatDateTime through Qt.locale().

var MS_PER_DAY = 86400000

// ---- Bar label formats. Right-clicking the clock walks these in order and
//      writes the result back to shell.json, so the label the bar shows and
//      the format the config stores are always the same thing.
//
// The locale-shaped time presets are each followed by their 12-hour twin, so
// the walk from a 24-hour label to the same label in AM/PM is a single right
// click rather than a lap of the ring. The ISO preset is deliberately left
// without one: ISO 8601 writes time on a 24-hour clock, so an AM/PM variant
// would contradict the only thing that format is for.
var CLOCK_FORMATS = [
  "dddd HH:mm",
  "dddd h:mm AP",
  "dddd HH:mm:ss",
  "dddd h:mm:ss AP",
  "HH:mm",
  "h:mm AP",
  "ddd d MMM HH:mm",
  "ddd d MMM h:mm AP",
  "d MMMM 'W'ww yyyy",
  "yyyy-MM-dd HH:mm"
]

// Vertical bars have room for a few stacked lines and nothing else, so the
// ring stays short. AM/PM costs a fourth line, which is why only the plain
// time carries it here.
var VERTICAL_CLOCK_FORMATS = [
  "HH\n—\nmm",
  "h\n—\nmm\nAP",
  "dd\nMMM\n'W'ww\n''yy",
  "HH\nmm"
]

// Whether a format prints seconds, so the widget can tick once a second only
// for the formats that show them. Quoted literals go first: the s in a 'Sat'
// is text rather than a token, and an opening quote with no closing one runs
// to the end of the format the way Qt reads it.
function clockNeedsSeconds(format) {
  var text = String(format === undefined || format === null ? "" : format)
  return /s/.test(text.replace(/'[^']*'?/g, ""))
}

// Whether a format is 24-hour (has "HH") vs 12-hour (has "h"/"AP") — the
// world-clock panel matches whichever convention the bar label is already
// using rather than asking for a separate preference.
function clockUses24Hour(format) {
  var text = String(format === undefined || format === null ? "" : format).replace(/'[^']*'?/g, "")
  return /HH/.test(text)
}

function clockFormats(vertical) {
  return vertical ? VERTICAL_CLOCK_FORMATS.slice() : CLOCK_FORMATS.slice()
}

// The presets in a fixed order, plus the configured alternate and current
// format when they are something else. The order must not depend on which
// entry is current: cycling writes the result back to shell.json, and a ring
// that reshuffled itself around the current value would bounce between two
// entries instead of walking.
function clockFormatRing(configured, configuredAlt, presets) {
  var ring = []
  var candidates = (presets || []).concat([configuredAlt, configured])
  for (var i = 0; i < candidates.length; i++) {
    var format = String(candidates[i] === undefined || candidates[i] === null ? "" : candidates[i])
    if (format === "" || ring.indexOf(format) !== -1) continue
    ring.push(format)
  }
  return ring.length > 0 ? ring : ["HH:mm"]
}

// Next entry after `current`. An unknown current format (a hand-written one
// that is not in the ring) starts the walk at the top.
function nextClockFormat(ring, current) {
  if (!ring || ring.length === 0) return ""
  var index = ring.indexOf(String(current === undefined || current === null ? "" : current))
  return ring[(index + 1) % ring.length]
}

function pad2(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

// ISO-8601 week number: the week owning the Thursday of that date's
// Monday-based week. Mirrors the clock widget's 'ww' format token.
function isoWeek(year, month, day) {
  var date = new Date(Date.UTC(year, month, day))
  var weekday = date.getUTCDay() || 7
  date.setUTCDate(date.getUTCDate() + 4 - weekday)
  var yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
  return Math.ceil(((date.getTime() - yearStart.getTime()) / MS_PER_DAY + 1) / 7)
}

// Two-digit ISO week, substituted into a format's 'ww' token before Qt
// formats it -- Qt has no ISO week specifier of its own.
function isoWeekLiteral(year, month, day) {
  return pad2(isoWeek(year, month, day))
}

// ---- World clock. Quickshell's QML JS engine has no Intl (confirmed: `new
//      Intl.DateTimeFormat(...)` throws ReferenceError), so an arbitrary
//      IANA zone's current UTC offset can't be computed in pure JS. Offsets
//      come from timezone-offsets.sh (reads the system's real zoneinfo db,
//      so it's DST-correct); everything below just applies a cached offset
//      to the already-ticking `today` Date.

function parseTimezonesSetting(value) {
  if (!Array.isArray(value)) return []
  var out = []
  for (var i = 0; i < value.length; i++) {
    var entry = value[i]
    if (!entry || typeof entry !== "object") continue
    var zone = String(entry.zone || "")
    if (zone === "") continue
    out.push({ zone: zone, label: String(entry.label || zoneDisplayLabel(zone)) })
  }
  return out
}

// One JSON object per line (see timezone-offsets.sh) -> {zone: {offsetMinutes, abbr, error}}.
function parseOffsetsOutput(text) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "") continue
    try {
      var parsed = JSON.parse(line)
      if (parsed && parsed.zone) out[parsed.zone] = parsed
    } catch (e) {
      // Ignore a malformed line rather than losing the whole batch.
    }
  }
  return out
}

// The standard trick for formatting a foreign zone without a real timezone
// database in JS: shift the absolute timestamp by the zone's UTC offset,
// then read the result with *UTC* getters. Reading local getters here would
// re-apply the system's own offset on top and double-shift the result.
function zoneShiftedDate(nowMs, offsetMinutes) {
  return new Date(nowMs + offsetMinutes * 60000)
}

function formatZoneTime(nowMs, offsetMinutes, use24h) {
  var d = zoneShiftedDate(nowMs, offsetMinutes)
  var hours = d.getUTCHours()
  var minutes = pad2(d.getUTCMinutes())
  if (use24h) return pad2(hours) + ":" + minutes
  var period = hours >= 12 ? "PM" : "AM"
  var h12 = hours % 12
  if (h12 === 0) h12 = 12
  return h12 + ":" + minutes + " " + period
}

// "" for today in that zone, else "Yesterday"/"Tomorrow" — the local day is
// derived the same shifted-then-UTC-read way, using the system's own
// getTimezoneOffset() (JS's one built-in zone-aware value: minutes *west*
// of UTC, positive for zones behind UTC — the opposite sign convention from
// the offsetMinutes this file otherwise uses, hence the negation below).
function formatZoneDayDelta(nowMs, offsetMinutes, localOffsetMinutesWestOfUtc) {
  var zoneDate = zoneShiftedDate(nowMs, offsetMinutes)
  var localDate = zoneShiftedDate(nowMs, -localOffsetMinutesWestOfUtc)
  var zoneDay = Date.UTC(zoneDate.getUTCFullYear(), zoneDate.getUTCMonth(), zoneDate.getUTCDate())
  var localDay = Date.UTC(localDate.getUTCFullYear(), localDate.getUTCMonth(), localDate.getUTCDate())
  var deltaDays = Math.round((zoneDay - localDay) / MS_PER_DAY)
  if (deltaDays === 0) return ""
  if (deltaDays === 1) return "Tomorrow"
  if (deltaDays === -1) return "Yesterday"
  return deltaDays > 0 ? ("+" + deltaDays + "d") : (deltaDays + "d")
}

// "America/New_York" -> "New York". Best-effort default label when a zone
// is first added; the user can still rename it.
function zoneDisplayLabel(zoneName) {
  var parts = String(zoneName || "").split("/")
  var last = parts[parts.length - 1] || zoneName
  return last.replace(/_/g, " ")
}

function filterZoneNames(allZones, query) {
  var list = Array.isArray(allZones) ? allZones : []
  var q = String(query || "").trim().toLowerCase()
  if (q === "") return list.slice(0, 40)
  var out = []
  for (var i = 0; i < list.length && out.length < 40; i++) {
    var zone = list[i]
    if (zone.toLowerCase().indexOf(q) !== -1) out.push(zone)
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    isoWeek: isoWeek,
    isoWeekLiteral: isoWeekLiteral,
    clockFormats: clockFormats,
    clockNeedsSeconds: clockNeedsSeconds,
    clockUses24Hour: clockUses24Hour,
    clockFormatRing: clockFormatRing,
    nextClockFormat: nextClockFormat,
    parseTimezonesSetting: parseTimezonesSetting,
    parseOffsetsOutput: parseOffsetsOutput,
    formatZoneTime: formatZoneTime,
    formatZoneDayDelta: formatZoneDayDelta,
    zoneDisplayLabel: zoneDisplayLabel,
    filterZoneNames: filterZoneNames
  }
}
