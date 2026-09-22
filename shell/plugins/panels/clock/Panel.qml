import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The clock's popup: today's date/time plus a world clock. Timezones are
// user-managed here (add/remove/rename), persisted the same way the bar
// label's own format is — through persistSettings -> updateEntryInline, no
// separate config file.
//
// BarWidget.qml owns the bar label and hands this panel the button to
// anchor against.
Panel {
  id: root
  moduleName: "roseshell.clock"
  ipcTarget: "roseshell.clock"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property date today: new Date()

  // Matches whichever convention the bar label already uses (right-click
  // cycling), rather than asking for a separate 12h/24h preference here.
  // Only the world-clock rows follow this automatically — the hero format
  // below is independently, freely editable.
  readonly property bool use24Hour: Model.clockUses24Hour(String(setting("format", "dddd HH:mm")))

  // Free-text Qt date/time format (same token syntax as the bar label's own
  // format setting), so "Friday, August 1, 2026 10:00 AM" and "21:00" are
  // both just different strings rather than needing separate settings.
  readonly property string heroFormat: String(setting("heroFormat", "dddd, MMMM d • h:mm AP"))
  property bool editingHeroFormat: false

  readonly property var timezones: Model.parseTimezonesSetting(setting("timezones", []))
  property var offsets: ({})
  property var allZoneNames: []
  property bool zoneNamesLoaded: false

  property bool cursorActive: false
  property int rowIndex: 0

  // "" | "addZone"
  property string activeForm: ""
  property string zoneQuery: ""
  property var filteredZoneNames: Model.filterZoneNames(root.allZoneNames, root.zoneQuery)

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(contentForeground, 1.55)

  function open() {
    refresh()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    activeForm = ""
    if (root.editingHeroFormat) root.cancelEditingHeroFormat()
    root.controller.hide()
  }

  function startEditingHeroFormat() {
    root.editingHeroFormat = true
    Qt.callLater(function() {
      heroFormatField.text = root.heroFormat
      heroFormatField.selectAll()
      heroFormatField.forceActiveFocus()
    })
  }

  function cancelEditingHeroFormat() {
    root.editingHeroFormat = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function commitHeroFormat(format) {
    var next = String(format || "").trim()
    if (next === "" || next === root.heroFormat) { cancelEditingHeroFormat(); return }
    persistSettings({ heroFormat: next })
    cancelEditingHeroFormat()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    root.refreshOffsets()
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function refreshOffsets() {
    if (root.timezones.length === 0 || offsetProcess.running) return
    var zoneNames = []
    for (var i = 0; i < root.timezones.length; i++) zoneNames.push(root.timezones[i].zone)
    offsetProcess.command = ["bash", (roseshellPath || "") + "/shell/plugins/panels/clock/timezone-offsets.sh"].concat(zoneNames)
    offsetProcess.running = true
  }

  function loadZoneNamesIfNeeded() {
    if (root.zoneNamesLoaded || zoneNamesProcess.running) return
    zoneNamesProcess.running = true
  }

  function addZone(zoneName, label) {
    var next = root.timezones.slice()
    next.push({ zone: zoneName, label: label || Model.zoneDisplayLabel(zoneName) })
    persistSettings({ timezones: next })
    activeForm = ""
    zoneQuery = ""
    Qt.callLater(root.refreshOffsets)
  }

  function removeZone(index) {
    var next = root.timezones.slice()
    if (index < 0 || index >= next.length) return
    next.splice(index, 1)
    persistSettings({ timezones: next })
  }

  function ensureCursor() {
    if (root.timezones.length === 0) { rowIndex = 0; return }
    if (rowIndex >= root.timezones.length) rowIndex = root.timezones.length - 1
    if (rowIndex < 0) rowIndex = 0
  }

  function moveCursor(dy) {
    cursorActive = true
    if (dy === 0 || root.timezones.length === 0) return
    rowIndex = Math.max(0, Math.min(root.timezones.length - 1, rowIndex + dy))
  }

  property string roseshellPath: Quickshell.env("ROSESHELL_PATH")

  onOpenedChanged: if (opened) {
    cursorActive = false
    rowIndex = 0
    refresh()
  }

  onTimezonesChanged: refreshOffsets()

  Process {
    id: offsetProcess
    running: false
    command: []
    stdout: StdioCollector { id: offsetStdout; waitForEnd: true; onStreamFinished: root._offsetOutput = text }
    onExited: function(exitCode) {
      if (exitCode === 0) root.offsets = Model.parseOffsetsOutput(String(offsetStdout.text || root._offsetOutput || ""))
    }
  }
  property string _offsetOutput: ""

  Process {
    id: zoneNamesProcess
    running: false
    command: ["timedatectl", "list-timezones"]
    stdout: StdioCollector { id: zoneNamesStdout; waitForEnd: true; onStreamFinished: root._zoneNamesOutput = text }
    onExited: function(exitCode) {
      root.zoneNamesLoaded = true
      if (exitCode === 0) {
        var text = String(zoneNamesStdout.text || root._zoneNamesOutput || "")
        root.allZoneNames = text.split("\n").filter(function(l) { return l.trim() !== "" })
      }
    }
  }
  property string _zoneNamesOutput: ""

  Timer {
    // Offsets are only ever wrong for the sliver of time around a DST
    // transition, so this just needs to be "often enough", not fast.
    id: offsetRefreshTimer
    interval: 15 * 60 * 1000
    repeat: true
    running: true
    onTriggered: root.refreshOffsets()
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.today = clock.date
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.activeForm !== "" || root.editingHeroFormat
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

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
            visible: !root.editingHeroFormat
            width: parent.width
            height: visible ? implicitHeight : 0
            title: Qt.formatDateTime(root.today, root.heroFormat)
            meta: "Click to change format"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: "󰥔"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.display
              }
            }

            TapHandler {
              onTapped: root.startEditingHeroFormat()
            }
          }

          Column {
            visible: root.editingHeroFormat
            width: parent.width
            height: visible ? implicitHeight : 0
            spacing: Style.space(6)

            TextField {
              id: heroFormatField
              width: parent.width
              placeholderText: "dddd, MMMM d, yyyy h:mm AP"

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.cancelEditingHeroFormat()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.commitHeroFormat(text)
                  event.accepted = true
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: "Preview: " + Qt.formatDateTime(root.today, heroFormatField.text)
              color: root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: [
                  { label: "Full", format: "dddd, MMMM d, yyyy h:mm AP" },
                  { label: "Short", format: "ddd h:mm AP" },
                  { label: "12h", format: "h:mm AP" },
                  { label: "24h", format: "HH:mm" }
                ]

                Button {
                  required property var modelData
                  text: modelData.label
                  onClicked: heroFormatField.text = modelData.format
                }
              }
            }

            Row {
              spacing: Style.space(8)
              Button { text: "Save"; onClicked: root.commitHeroFormat(heroFormatField.text) }
              Button { text: "Cancel"; onClicked: root.cancelEditingHeroFormat() }
            }
          }

          PanelSeparator { foreground: root.contentForeground }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "WORLD CLOCK"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            Text {
              visible: root.timezones.length === 0
              width: parent.width
              text: "No timezones added yet."
              color: root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: zoneColumn
              visible: root.timezones.length > 0
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.timezones
                ZoneRow {
                  required property var modelData
                  required property int index
                  width: zoneColumn.width
                  entry: modelData
                  rowIndex: index
                }
              }
            }

            Row {
              width: parent.width
              visible: root.activeForm === ""

              Button {
                text: "+ Add timezone"
                onClicked: {
                  root.activeForm = "addZone"
                  root.loadZoneNamesIfNeeded()
                  Qt.callLater(function() { zoneSearchField.forceActiveFocus() })
                }
              }
            }

            Column {
              visible: root.activeForm === "addZone"
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: zoneSearchField
                width: parent.width
                placeholderText: root.zoneNamesLoaded ? "Search timezones…" : "Loading timezones…"
                enabled: root.zoneNamesLoaded
                onTextChanged: root.zoneQuery = text
              }

              Column {
                width: parent.width
                spacing: Style.space(2)

                Repeater {
                  model: root.filteredZoneNames
                  ZoneOptionRow {
                    required property string modelData
                    width: parent.width
                    zoneName: modelData
                  }
                }

                Text {
                  visible: root.zoneNamesLoaded && root.filteredZoneNames.length === 0
                  width: parent.width
                  text: "No matching timezones."
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }

              Row {
                Button {
                  text: "Cancel"
                  onClicked: { root.activeForm = ""; root.zoneQuery = "" }
                }
              }
            }
          }
        }
      }
    }
  }

  component ZoneRow: CursorSurface {
    id: zoneRow
    property var entry: null
    property int rowIndex: 0
    readonly property var offset: entry ? root.offsets[entry.zone] : null

    hasCursor: root.cursorActive && root.rowIndex === rowIndex
    foreground: root.contentForeground

    implicitHeight: zoneContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onEntered: { root.cursorActive = true; root.rowIndex = zoneRow.rowIndex }
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      ColumnLayout {
        id: zoneContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: zoneRow.entry ? zoneRow.entry.label : ""
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: {
            if (!zoneRow.offset) return zoneRow.entry ? zoneRow.entry.zone : ""
            if (zoneRow.offset.error) return "Unknown zone"
            var abbr = zoneRow.offset.abbr ? (" " + zoneRow.offset.abbr) : ""
            return (zoneRow.entry ? zoneRow.entry.zone : "") + abbr
          }
          color: root.dim
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: !!(zoneRow.offset && !zoneRow.offset.error)
        text: zoneRow.offset && !zoneRow.offset.error
          ? Model.formatZoneDayDelta(root.today.getTime(), zoneRow.offset.offsetMinutes, root.today.getTimezoneOffset())
          : ""
        color: root.dim
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        textFormat: Text.PlainText
        text: zoneRow.offset && !zoneRow.offset.error
          ? Model.formatZoneTime(root.today.getTime(), zoneRow.offset.offsetMinutes, root.use24Hour)
          : "––:––"
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        Layout.alignment: Qt.AlignVCenter
      }

      PanelActionButton {
        iconText: "×"
        tooltipText: "Remove"
        foreground: root.contentForeground
        hoverColor: root.bar ? root.bar.urgent : Color.urgent
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.removeZone(zoneRow.rowIndex)
      }
    }
  }

  component ZoneOptionRow: CursorSurface {
    id: optionRow
    property string zoneName: ""

    foreground: root.contentForeground
    implicitHeight: optionText.implicitHeight + Style.space(6)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: parent.hasCursor = true
      onExited: parent.hasCursor = false
      onClicked: root.addZone(optionRow.zoneName, Model.zoneDisplayLabel(optionRow.zoneName))
    }

    Text {
      id: optionText
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      text: optionRow.zoneName
      color: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
  }
}
