import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// Long-lived state for the Calendar plugin, modeled on the Dropbox/Tailscale
// Service.qml shape: own the poll timer and every Process, expose plain
// properties the bar widget and panel both read. All actual CalDAV/ICS work
// happens in the co-located calendar.py helper (Process + JSON on stdout),
// never inline here — this file only orchestrates and parses.
Item {
  id: root

  property var settings: ({})
  property string roseshellPath: Quickshell.env("ROSESHELL_PATH")
  readonly property string helperPath: (roseshellPath || "") + "/shell/plugins/panels/calendar/calendar.py"

  property var accounts: []
  property var events: []
  property var syncErrors: []
  property string lastSyncAt: ""
  property bool syncing: false
  property string lastError: ""

  // Separate from lastError/syncing: an in-flight add-account/create-event/
  // etc. action, so a stale sync error doesn't bury a fresh action result.
  property bool actionBusy: false
  property string actionStatus: ""
  property string actionError: ""

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 300, 30, 3600)
  readonly property bool busy: syncProcess.running || actionBusy

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function sync() {
    if (syncProcess.running || helperPath === "/shell/plugins/panels/calendar/calendar.py") return
    syncing = true
    syncProcess.command = ["python3", helperPath, "sync"]
    syncProcess.running = true
  }

  function addIcloud(email, password) {
    if (actionBusy) return
    actionBusy = true
    actionStatus = "Connecting to iCloud…"
    actionError = ""
    addIcloudProcess.secret = password
    addIcloudProcess.command = ["python3", helperPath, "add-icloud", email]
    addIcloudProcess.running = true
  }

  function addIcs(url, label, provider) {
    if (actionBusy) return
    actionBusy = true
    actionStatus = "Adding calendar feed…"
    actionError = ""
    addIcsProcess.command = ["python3", helperPath, "add-ics", url, "--label", label, "--provider", provider || "ics"]
    addIcsProcess.running = true
  }

  function removeAccount(accountId) {
    if (actionBusy) return
    actionBusy = true
    actionStatus = "Removing account…"
    actionError = ""
    removeAccountProcess.command = ["python3", helperPath, "remove-account", accountId]
    removeAccountProcess.running = true
  }

  // payload: { accountId, calendarUrl, title, start, end, allDay, location }
  function createEvent(payload) {
    if (actionBusy) return
    actionBusy = true
    actionStatus = "Saving event…"
    actionError = ""
    createEventProcess.payload = JSON.stringify(payload)
    createEventProcess.command = ["python3", helperPath, "create-event"]
    createEventProcess.running = true
  }

  function deleteEvent(accountId, calendarUrl, uid) {
    if (actionBusy) return
    actionBusy = true
    actionStatus = "Deleting event…"
    actionError = ""
    deleteEventProcess.payload = JSON.stringify({ accountId: accountId, calendarUrl: calendarUrl, uid: uid })
    deleteEventProcess.command = ["python3", helperPath, "delete-event"]
    deleteEventProcess.running = true
  }

  function parseActionResult(text, actionLabel) {
    try {
      var parsed = JSON.parse(text)
      if (parsed && parsed.ok) {
        actionStatus = ""
        actionError = ""
        sync()
        accountsFile.reload()
      } else {
        actionError = (parsed && parsed.error) ? String(parsed.error) : (actionLabel + " failed")
        actionStatus = ""
      }
    } catch (e) {
      actionError = actionLabel + " failed"
      actionStatus = ""
    }
  }

  FileView {
    id: accountsFile
    path: Quickshell.env("HOME") + "/.local/state/roseshell/settings/calendar.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.accounts = Model.parseAccountsPayload(text()).accounts
    onLoadFailed: root.accounts = []
  }

  FileView {
    id: eventsFile
    path: Quickshell.env("HOME") + "/.local/state/roseshell/calendar/events.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var parsed = Model.parseEventsPayload(text())
      root.events = parsed.events
      root.syncErrors = parsed.errors
      root.lastSyncAt = parsed.generatedAt
    }
    onLoadFailed: {
      root.events = []
      root.syncErrors = []
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.sync()
  }

  Timer {
    // A CalDAV round-trip to a slow/unreachable server can hang well past a
    // normal poll interval. Reap it so the next scheduled sync isn't skipped
    // forever because `syncProcess.running` never went false.
    id: pollWatchdog
    interval: 20000
    repeat: false
    onTriggered: if (syncProcess.running) syncProcess.running = false
  }

  onSyncingChanged: if (syncing) pollWatchdog.restart()

  Process {
    id: syncProcess
    running: false
    command: []
    stdout: StdioCollector { id: syncStdout; waitForEnd: true; onStreamFinished: root._syncOutput = text }
    stderr: StdioCollector { id: syncStderr; waitForEnd: true; onStreamFinished: root._syncError = text }
    onExited: function(exitCode) {
      root.syncing = false
      var stdout = String(syncStdout.text || root._syncOutput || "")
      var stderr = String(syncStderr.text || root._syncError || "")
      if (exitCode !== 0) {
        root.lastError = (stderr || stdout || "Calendar sync failed").trim()
      } else {
        root.lastError = ""
      }
      // events.json is written by the helper itself; the FileView watch picks
      // up the new content on its own. Nothing further to parse here.
    }
  }
  property string _syncOutput: ""
  property string _syncError: ""

  Process {
    id: addIcloudProcess
    property string secret: ""
    running: false
    command: []
    stdinEnabled: true
    stdout: StdioCollector { id: addIcloudStdout; waitForEnd: true; onStreamFinished: root._addIcloudOutput = text }
    onStarted: { write(secret + "\n"); secret = "" }
    onExited: function(exitCode) {
      root.actionBusy = false
      root.parseActionResult(String(addIcloudStdout.text || root._addIcloudOutput || ""), "Adding iCloud account")
    }
  }
  property string _addIcloudOutput: ""

  Process {
    id: addIcsProcess
    running: false
    command: []
    stdout: StdioCollector { id: addIcsStdout; waitForEnd: true; onStreamFinished: root._addIcsOutput = text }
    onExited: function(exitCode) {
      root.actionBusy = false
      root.parseActionResult(String(addIcsStdout.text || root._addIcsOutput || ""), "Adding calendar feed")
    }
  }
  property string _addIcsOutput: ""

  Process {
    id: removeAccountProcess
    running: false
    command: []
    stdout: StdioCollector { id: removeAccountStdout; waitForEnd: true; onStreamFinished: root._removeAccountOutput = text }
    onExited: function(exitCode) {
      root.actionBusy = false
      root.parseActionResult(String(removeAccountStdout.text || root._removeAccountOutput || ""), "Removing account")
    }
  }
  property string _removeAccountOutput: ""

  Process {
    id: createEventProcess
    property string payload: ""
    running: false
    command: []
    stdinEnabled: true
    stdout: StdioCollector { id: createEventStdout; waitForEnd: true; onStreamFinished: root._createEventOutput = text }
    onStarted: { write(payload + "\n"); payload = "" }
    onExited: function(exitCode) {
      root.actionBusy = false
      root.parseActionResult(String(createEventStdout.text || root._createEventOutput || ""), "Saving event")
    }
  }
  property string _createEventOutput: ""

  Process {
    id: deleteEventProcess
    property string payload: ""
    running: false
    command: []
    stdinEnabled: true
    stdout: StdioCollector { id: deleteEventStdout; waitForEnd: true; onStreamFinished: root._deleteEventOutput = text }
    onStarted: { write(payload + "\n"); payload = "" }
    onExited: function(exitCode) {
      root.actionBusy = false
      root.parseActionResult(String(deleteEventStdout.text || root._deleteEventOutput || ""), "Deleting event")
    }
  }
  property string _deleteEventOutput: ""
}
