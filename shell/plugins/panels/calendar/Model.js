// Pure JSON/data plumbing for the calendar plugin. No Qt.* calls here (kept
// consistent with the clock plugin's Model.js convention) — QML owns all
// locale-aware time/date formatting, this only shapes the data.

function parseEventsPayload(text) {
  var fallback = { events: [], errors: [], generatedAt: "" }
  if (!text) return fallback
  try {
    var parsed = JSON.parse(text)
    return {
      events: Array.isArray(parsed.events) ? parsed.events : [],
      errors: Array.isArray(parsed.errors) ? parsed.errors : [],
      generatedAt: String(parsed.generatedAt || "")
    }
  } catch (e) {
    return fallback
  }
}

function parseAccountsPayload(text) {
  if (!text) return { accounts: [] }
  try {
    var parsed = JSON.parse(text)
    return { accounts: Array.isArray(parsed.accounts) ? parsed.accounts : [] }
  } catch (e) {
    return { accounts: [] }
  }
}

// "2026-09-22T14:00:00-04:00" -> "2026-09-22". Deliberately string-sliced
// rather than parsed through Date so an all-day event's bare-date value
// ("2026-09-22") passes through unchanged instead of being reinterpreted in
// the reader's local timezone.
function dateKeyFromIso(iso) {
  return String(iso || "").slice(0, 10)
}

function eventsForDateKey(events, dateKey) {
  var list = Array.isArray(events) ? events : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (dateKeyFromIso(list[i].start) === dateKey) out.push(list[i])
  }
  out.sort(function(a, b) { return String(a.start).localeCompare(String(b.start)) })
  return out
}

// The event the bar label should lead with: the first of today's events
// that hasn't ended yet, or null once the day's events are all in the past.
function nextUpcomingEvent(todaysEvents, nowIso) {
  var now = String(nowIso || "")
  for (var i = 0; i < todaysEvents.length; i++) {
    var ev = todaysEvents[i]
    if (ev.allDay || String(ev.end) > now) return ev
  }
  return null
}

function accountById(accounts, accountId) {
  var list = Array.isArray(accounts) ? accounts : []
  for (var i = 0; i < list.length; i++) {
    if (list[i].id === accountId) return list[i]
  }
  return null
}

function enabledCalendarOptions(accounts) {
  var list = Array.isArray(accounts) ? accounts : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var account = list[i]
    if (!account.enabled) continue
    var calendars = Array.isArray(account.calendars) ? account.calendars : []
    for (var j = 0; j < calendars.length; j++) {
      var cal = calendars[j]
      if (!cal.enabled) continue
      // create-event only works against a writable (caldav) account today —
      // ics feed accounts are read-only subscriptions.
      if (account.type !== "caldav") continue
      out.push({
        value: account.id + "\u0000" + cal.url,
        label: account.label + " — " + cal.displayName
      })
    }
  }
  return out
}
