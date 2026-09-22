import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "roseshell.calendar"
  ipcTarget: "roseshell.calendar"
  manageIpc: false

  property string roseshellPath: Quickshell.env("ROSESHELL_PATH")
  property string focusSection: "today"
  property int rowIndex: 0
  property bool cursorActive: false

  // "" | "addIcloud" | "addIcs" | "newEvent"
  property string activeForm: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barIconColor: calendar.events.length > 0 ? barForeground : Qt.darker(barForeground, 1.55)

  readonly property date today: new Date()
  readonly property string todayKey: Qt.formatDate(today, "yyyy-MM-dd")
  readonly property var todaysEvents: Model.eventsForDateKey(calendar.events, todayKey)
  readonly property var nextEvent: Model.nextUpcomingEvent(todaysEvents, today.toISOString())
  readonly property string barLabel: {
    if (calendar.syncing && calendar.events.length === 0) return "…"
    if (nextEvent) return eventTimeLabel(nextEvent) + " " + nextEvent.title
    if (todaysEvents.length > 0) return todaysEvents.length + " today"
    return ""
  }

  function eventTimeLabel(ev) {
    if (!ev) return ""
    if (ev.allDay) return "All day"
    var d = new Date(ev.start)
    return isNaN(d.getTime()) ? "" : Qt.formatTime(d, "h:mm AP")
  }

  function eventRangeLabel(ev) {
    if (!ev) return ""
    if (ev.allDay) return "All day"
    var s = new Date(ev.start)
    var e = new Date(ev.end)
    if (isNaN(s.getTime())) return ""
    var out = Qt.formatTime(s, "h:mm AP")
    if (!isNaN(e.getTime()) && e.getTime() !== s.getTime()) out += " – " + Qt.formatTime(e, "h:mm AP")
    return out
  }

  function rowCount(section) {
    return section === "today" ? todaysEvents.length : calendar.accounts.length
  }

  // Re-clamps the cursor after live data changes (a sync landing, an
  // account being added/removed) so it never points past the end of a list
  // that just got shorter.
  function ensureCursor() {
    if (rowCount(focusSection) === 0) {
      focusSection = todaysEvents.length > 0 ? "today" : "accounts"
    }
    var count = rowCount(focusSection)
    if (rowIndex < 0) rowIndex = 0
    if (count > 0 && rowIndex >= count) rowIndex = count - 1
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    if (dy === 0) return
    var count = rowCount(focusSection)
    if (dy > 0 && rowIndex >= count - 1) {
      // Fall through to the next section, if any.
      if (focusSection === "today" && calendar.accounts.length > 0) { focusSection = "accounts"; rowIndex = 0 }
      return
    }
    if (dy < 0 && rowIndex <= 0) {
      if (focusSection === "accounts" && todaysEvents.length > 0) { focusSection = "today"; rowIndex = todaysEvents.length - 1 }
      return
    }
    rowIndex = Math.max(0, Math.min(count - 1, rowIndex + dy))
  }

  // No per-account enable/disable toggle yet — the backend only supports
  // add/remove (see calendar.py), and removing is already one click on the
  // row's × button, so Enter-to-activate has nothing to do here for now.

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    rowIndex = 0
    focusSection = todaysEvents.length > 0 ? "today" : "accounts"
    if (panelFlick) panelFlick.contentY = 0
    calendar.sync()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: calendar
    settings: root.settings
    roseshellPath: root.roseshellPath
  }

  Connections {
    target: calendar
    function onAccountsChanged() { root.ensureCursor() }
    function onEventsChanged() { root.ensureCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { calendar.sync(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barLabel !== "" ? "  " + root.barLabel : ""
    onPressed: function(b) {
      if (b === Qt.MiddleButton) calendar.sync()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.activeForm !== ""
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") calendar.sync()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "Calendar"
            meta: Qt.formatDate(root.today, "dddd, MMMM d")
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              PanelActionButton {
                iconText: calendar.syncing ? "◌" : ""
                tooltipText: calendar.lastSyncAt !== "" ? ("Last synced " + calendar.lastSyncAt) : "Sync now"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !calendar.syncing
                onClicked: calendar.sync()
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: calendar.actionError !== "" || calendar.lastError !== "" || calendar.syncErrors.length > 0
            width: parent.width
            text: calendar.actionError !== "" ? calendar.actionError
              : (calendar.lastError !== "" ? calendar.lastError : calendar.syncErrors.join("; "))
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            visible: calendar.actionStatus !== ""
            width: parent.width
            text: calendar.actionStatus
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(10)

            Row {
              width: parent.width
              PanelSectionHeader {
                text: "TODAY"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
            }

            Text {
              visible: root.todaysEvents.length === 0
              width: parent.width
              text: calendar.accounts.length === 0 ? "No calendar accounts connected yet." : "Nothing on your calendar today."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: eventColumn
              visible: root.todaysEvents.length > 0
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.todaysEvents
                EventRow {
                  required property var modelData
                  required property int index
                  width: eventColumn.width
                  ev: modelData
                  rowIndex: index
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "ACCOUNTS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: calendar.accounts.length === 0
              width: parent.width
              text: "No accounts yet — add iCloud below."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: accountColumn
              visible: calendar.accounts.length > 0
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: calendar.accounts
                AccountRow {
                  required property var modelData
                  required property int index
                  width: accountColumn.width
                  account: modelData
                  rowIndex: index
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)
              visible: root.activeForm === ""

              Button {
                text: "+ iCloud"
                onClicked: { root.activeForm = "addIcloud"; Qt.callLater(function() { icloudEmailField.forceActiveFocus() }) }
              }
              Button {
                text: "+ ICS feed"
                onClicked: { root.activeForm = "addIcs"; Qt.callLater(function() { icsUrlField.forceActiveFocus() }) }
              }
            }

            Column {
              visible: root.activeForm === "addIcloud"
              width: parent.width
              spacing: Style.space(6)

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: "Apple ID + an app-specific password (appleid.apple.com → Sign-In and Security → App-Specific Passwords) — never your real Apple ID password."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              TextField {
                id: icloudEmailField
                width: parent.width
                placeholderText: "you@icloud.com"
              }
              TextField {
                id: icloudPasswordField
                width: parent.width
                password: true
                placeholderText: "app-specific password"
                onAccepted: icloudConnectButton.clicked()
              }

              Row {
                spacing: Style.space(8)
                Button {
                  id: icloudConnectButton
                  text: calendar.actionBusy ? "Connecting…" : "Connect"
                  enabled: !calendar.actionBusy && icloudEmailField.text !== "" && icloudPasswordField.text !== ""
                  onClicked: {
                    calendar.addIcloud(icloudEmailField.text, icloudPasswordField.text)
                    icloudPasswordField.text = ""
                  }
                }
                Button {
                  text: "Cancel"
                  onClicked: { root.activeForm = ""; icloudEmailField.text = ""; icloudPasswordField.text = "" }
                }
              }
            }

            Column {
              visible: root.activeForm === "addIcs"
              width: parent.width
              spacing: Style.space(6)

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: "A read-only secret iCal/ICS feed link (Google Calendar settings → “Secret address in iCal format”, or Outlook → “Publish a calendar”)."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              TextField {
                id: icsLabelField
                width: parent.width
                placeholderText: "Label, e.g. Work (Google)"
              }
              TextField {
                id: icsUrlField
                width: parent.width
                placeholderText: "https://calendar.google.com/.../basic.ics"
                onAccepted: icsAddButton.clicked()
              }

              Row {
                spacing: Style.space(8)
                Button {
                  id: icsAddButton
                  text: calendar.actionBusy ? "Adding…" : "Add"
                  enabled: !calendar.actionBusy && icsUrlField.text !== "" && icsLabelField.text !== ""
                  onClicked: calendar.addIcs(icsUrlField.text, icsLabelField.text, "ics")
                }
                Button {
                  text: "Cancel"
                  onClicked: { root.activeForm = ""; icsLabelField.text = ""; icsUrlField.text = "" }
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(10)

            Row {
              width: parent.width
              spacing: Style.space(8)
              PanelSectionHeader {
                text: "NEW EVENT"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
            }

            Button {
              visible: root.activeForm === "" && Model.enabledCalendarOptions(calendar.accounts).length > 0
              text: "+ New event"
              onClicked: { root.activeForm = "newEvent"; Qt.callLater(function() { eventTitleField.forceActiveFocus() }) }
            }

            Text {
              visible: root.activeForm === "" && Model.enabledCalendarOptions(calendar.accounts).length === 0
              width: parent.width
              text: "Connect a writable (iCloud) account to create events."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Column {
              visible: root.activeForm === "newEvent"
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: eventTitleField
                width: parent.width
                placeholderText: "Title"
              }

              Dropdown {
                id: eventCalendarDropdown
                width: parent.width
                label: "Calendar"
                options: Model.enabledCalendarOptions(calendar.accounts)
                value: options.length > 0 ? Model.enabledCalendarOptions(calendar.accounts)[0].value : ""
              }

              Row {
                width: parent.width
                spacing: Style.space(8)
                TextField {
                  id: eventDateField
                  width: (parent.width - Style.space(8)) / 2
                  placeholderText: "YYYY-MM-DD"
                  text: root.todayKey
                }
                Row {
                  spacing: Style.space(6)
                  Text {
                    text: "All day"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  ToggleSwitch {
                    id: eventAllDayToggle
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(8)
                visible: !eventAllDayToggle.checked
                TextField {
                  id: eventStartField
                  width: (parent.width - Style.space(8)) / 2
                  placeholderText: "Start HH:MM"
                  text: "09:00"
                }
                TextField {
                  id: eventEndField
                  width: (parent.width - Style.space(8)) / 2
                  placeholderText: "End HH:MM"
                  text: "10:00"
                }
              }

              TextField {
                id: eventLocationField
                width: parent.width
                placeholderText: "Location (optional)"
              }

              Text {
                textFormat: Text.PlainText
                visible: eventFormError !== ""
                width: parent.width
                text: eventFormError
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Row {
                spacing: Style.space(8)
                Button {
                  text: calendar.actionBusy ? "Saving…" : "Save"
                  enabled: !calendar.actionBusy && eventTitleField.text !== "" && eventCalendarDropdown.value !== ""
                  onClicked: root.submitNewEvent()
                }
                Button {
                  text: "Cancel"
                  onClicked: root.resetEventForm()
                }
              }
            }
          }
        }
      }
    }
  }

  property string eventFormError: ""

  function resetEventForm() {
    activeForm = ""
    eventFormError = ""
    eventTitleField.text = ""
    eventLocationField.text = ""
    eventDateField.text = todayKey
    eventStartField.text = "09:00"
    eventEndField.text = "10:00"
    eventAllDayToggle.checked = false
  }

  function submitNewEvent() {
    eventFormError = ""
    var parts = eventCalendarDropdown.value.split("\u0000")
    if (parts.length !== 2) { eventFormError = "Pick a calendar."; return }

    var allDay = eventAllDayToggle.checked
    var startIso, endIso
    if (allDay) {
      startIso = eventDateField.text + "T00:00:00"
      endIso = eventDateField.text + "T00:00:00"
    } else {
      startIso = eventDateField.text + "T" + eventStartField.text + ":00"
      endIso = eventDateField.text + "T" + eventEndField.text + ":00"
    }
    if (isNaN(new Date(startIso).getTime()) || isNaN(new Date(endIso).getTime())) {
      eventFormError = "Check the date/time fields."
      return
    }

    calendar.createEvent({
      accountId: parts[0],
      calendarUrl: parts[1],
      title: eventTitleField.text,
      start: startIso,
      end: endIso,
      allDay: allDay,
      location: eventLocationField.text
    })
    resetEventForm()
  }

  component EventRow: CursorSurface {
    id: eventRow
    property var ev: null
    property int rowIndex: 0

    hasCursor: root.cursorActive && root.focusSection === "today" && root.rowIndex === rowIndex
    foreground: root.foreground

    implicitHeight: eventContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onEntered: { root.cursorActive = true; root.focusSection = "today"; root.rowIndex = eventRow.rowIndex }
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Rectangle {
        width: Style.space(8)
        height: Style.space(8)
        radius: width / 2
        color: eventRow.ev ? eventRow.ev.color : "#888888"
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: eventContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: eventRow.ev ? eventRow.ev.title : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: eventRow.ev ? (root.eventRangeLabel(eventRow.ev) + (eventRow.ev.location ? " · " + eventRow.ev.location : "")) : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component AccountRow: CursorSurface {
    id: accountRow
    property var account: null
    property int rowIndex: 0

    hasCursor: root.cursorActive && root.focusSection === "accounts" && root.rowIndex === rowIndex
    foreground: root.foreground

    implicitHeight: accountContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onEntered: { root.cursorActive = true; root.focusSection = "accounts"; root.rowIndex = accountRow.rowIndex }
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      ColumnLayout {
        id: accountContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: accountRow.account ? accountRow.account.label : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: accountRow.account ? (accountRow.account.type === "caldav" ? "iCloud · read/write" : "ICS feed · read-only") : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: "×"
        tooltipText: "Remove account"
        foreground: root.foreground
        hoverColor: root.urgent
        Layout.alignment: Qt.AlignVCenter
        onClicked: calendar.removeAccount(accountRow.account.id)
      }
    }
  }
}
