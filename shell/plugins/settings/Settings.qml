import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// A small settings panel: appearance (theme/background/font/cursor/icons),
// a few shell-wide toggles, and plugin enable/disable. Everything here
// applies live via the same CLI/IPC plumbing the rest of the shell uses --
// nothing is reimplemented, just surfaced.
Item {
  id: root

  property string roseshellPath: Quickshell.env("ROSESHELL_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int cardWidth: Math.min(Style.space(460), panel.width - Style.gapsOut * 2)
  property int cardMaxHeight: Math.max(Style.space(300), panel.height - Style.gapsOut * 6)

  property string activeTab: "appearance" // appearance | shell | plugins

  function open(payloadJson) {
    root.opened = true
    root.activeTab = "appearance"
    root.refreshAll()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "roseshell.settings")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function refreshAll() {
    themeList.running = true
    themeCurrent.running = true
    backgroundList.running = true
    backgroundCurrent.running = true
    fontList.running = true
    fontCurrent.running = true
    cursorList.running = true
    cursorCurrent.running = true
    iconList.running = true
    iconCurrent.running = true
    shellConfigProbe.running = true
    nightlightProbe.running = true
    pluginListProbe.running = true
  }

  function stripQuotes(s) {
    var t = String(s || "").trim()
    if (t.length >= 2 && t.charAt(0) === "'" && t.charAt(t.length - 1) === "'")
      return t.substring(1, t.length - 1)
    return t
  }

  // ============================================================ appearance

  property var themeOptions: []
  property string themeValue: ""
  property var backgroundOptions: []
  property string backgroundValue: ""
  property var fontOptions: []
  property string fontValue: ""
  property var cursorOptions: []
  property string cursorValue: ""
  property var iconOptions: []
  property string iconValue: ""

  Process {
    id: themeList
    command: ["bash", "-c", "roseshell-theme-list"]
    property var lines: []
    onStarted: lines = []
    stdout: SplitParser { onRead: function(line) { if (line) themeList.lines.push(line) } }
    onExited: root.themeOptions = themeList.lines
  }

  Process {
    id: themeCurrent
    command: ["bash", "-c", "roseshell-theme-current"]
    stdout: SplitParser { onRead: function(line) { if (line) root.themeValue = line } }
  }

  // Backgrounds are scoped to the current theme (plus any user overrides in
  // ~/.config/roseshell/backgrounds/<theme>/), same set roseshell-theme-bg-next
  // cycles through. Listed as {value: full path, label: prettified name}
  // since roseshell-theme-bg-set needs the path, not the display name.
  readonly property string backgroundListCmd: "THEME_NAME=$(cat \"$HOME/.local/state/roseshell/current/theme.name\" 2>/dev/null); "
    + "find -L \"$HOME/.config/roseshell/backgrounds/$THEME_NAME/\" \"$HOME/.local/state/roseshell/current/theme/backgrounds/\" -maxdepth 1 -type f "
    + "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' "
    + "-o -iname '*.mp4' -o -iname '*.m4v' -o -iname '*.mov' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.avi' \\) 2>/dev/null "
    + "| sort -u | while read -r p; do label=$(basename -- \"$p\" | perl -pe 's/\\.[^.]+$//; s/^\\d+-//; s/-/ /g; s/\\b(\\w)/\\U$1/g'); printf '%s\\t%s\\n' \"$p\" \"$label\"; done"

  Process {
    id: backgroundList
    command: ["bash", "-c", root.backgroundListCmd]
    property var items: []
    onStarted: items = []
    stdout: SplitParser {
      onRead: function(line) {
        if (!line) return
        var i = line.indexOf("\t")
        if (i < 0) return
        backgroundList.items.push({ value: line.substring(0, i), label: line.substring(i + 1) })
      }
    }
    onExited: root.backgroundOptions = backgroundList.items
  }

  Process {
    id: backgroundCurrent
    command: ["bash", "-c", "readlink -f \"$HOME/.local/state/roseshell/current/background\""]
    stdout: SplitParser { onRead: function(line) { if (line) root.backgroundValue = line } }
  }

  Process {
    id: fontList
    command: ["bash", "-c", "roseshell-font-list"]
    property var lines: []
    onStarted: lines = []
    stdout: SplitParser { onRead: function(line) { if (line) fontList.lines.push(line) } }
    onExited: root.fontOptions = fontList.lines
  }

  Process {
    id: fontCurrent
    command: ["bash", "-c", "roseshell-font-current"]
    stdout: SplitParser { onRead: function(line) { if (line) root.fontValue = line } }
  }

  // Upstream never shipped a CLI for cursor/icon theme listing, so these are
  // enumerated by hand: any icons/*/ with a cursors/ subdir is a cursor
  // theme, any with an index.theme is an icon theme (the sets overlap).
  readonly property string iconDirGlob: "\"$HOME/.local/share/icons\" \"$HOME/.icons\" /usr/share/icons"

  Process {
    id: cursorList
    command: ["bash", "-c", "for d in " + root.iconDirGlob + "; do [ -d \"$d\" ] && find \"$d\" -mindepth 1 -maxdepth 1 -type d; done | while read -r t; do [ -d \"$t/cursors\" ] && basename \"$t\"; done | sort -u"]
    property var lines: []
    onStarted: lines = []
    stdout: SplitParser { onRead: function(line) { if (line) cursorList.lines.push(line) } }
    onExited: root.cursorOptions = cursorList.lines
  }

  Process {
    id: cursorCurrent
    command: ["bash", "-c", "gsettings get org.gnome.desktop.interface cursor-theme"]
    stdout: SplitParser { onRead: function(line) { if (line) root.cursorValue = root.stripQuotes(line) } }
  }

  Process {
    id: iconList
    command: ["bash", "-c", "for d in " + root.iconDirGlob + "; do [ -d \"$d\" ] && find \"$d\" -mindepth 1 -maxdepth 1 -type d; done | while read -r t; do [ -f \"$t/index.theme\" ] && basename \"$t\"; done | sort -u"]
    property var lines: []
    onStarted: lines = []
    stdout: SplitParser { onRead: function(line) { if (line) iconList.lines.push(line) } }
    onExited: root.iconOptions = iconList.lines
  }

  Process {
    id: iconCurrent
    command: ["bash", "-c", "gsettings get org.gnome.desktop.interface icon-theme"]
    stdout: SplitParser { onRead: function(line) { if (line) root.iconValue = root.stripQuotes(line) } }
  }

  function applyTheme(name) {
    root.themeValue = name
    Util.execDetached("roseshell-theme-set " + Util.shellQuote(name))
    // roseshell-theme-set takes ~800ms and picks its own starting background;
    // reload the background row once it's settled rather than racing it.
    backgroundRefreshDelay.restart()
  }

  function applyBackground(path) {
    root.backgroundValue = path
    Util.execDetached("roseshell-theme-bg-set " + Util.shellQuote(path))
  }

  // Derives a palette from the current background and applies it as the
  // generated "wallpaper" theme (see roseshell-theme-from-background). The script
  // also re-homes the background under that theme, so once it exits reload the
  // theme and background rows to match.
  function matchThemeToBackground() {
    if (!root.backgroundValue) return
    matchThemeProc.command = ["bash", "-c", "roseshell-theme-from-background \"$1\"", "bash", root.backgroundValue]
    matchThemeProc.running = true
  }

  Process {
    id: matchThemeProc
    onExited: function(code) {
      themeCurrent.running = true
      themeList.running = true
      backgroundList.running = true
      backgroundCurrent.running = true
    }
  }

  Timer {
    id: backgroundRefreshDelay
    interval: 1200
    onTriggered: {
      backgroundList.running = true
      backgroundCurrent.running = true
    }
  }

  // Reuses the shell's own first-party image picker (the "image-selector" IPC
  // target) rather than building a file dialog from scratch. It's a
  // request/response pair over two temp files: `open` tells it which dirs to
  // browse and where to write the answer, then this process polls the done
  // file (the picker touches it on both pick and cancel) and prints whatever
  // ended up in the selection file, if anything.
  function browseForBackground() {
    var home = Quickshell.env("HOME")
    var dirs = home + "/Pictures\n" + home + "/Downloads"
    var runtimeDir = Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    var script = "sel=$(mktemp -u " + Util.shellQuote(runtimeDir + "/roseshell-bg-sel-XXXXXX") + "); "
      + "done_f=$(mktemp -u " + Util.shellQuote(runtimeDir + "/roseshell-bg-done-XXXXXX") + "); "
      + "roseshell-shell image-selector open " + Util.shellQuote(dirs) + " '' " + Util.shellQuote(root.backgroundValue)
      + " \"$sel\" \"$done_f\" true true >/dev/null; "
      + "for i in $(seq 1 600); do [ -e \"$done_f\" ] && break; sleep 0.2; done; "
      + "[ -f \"$sel\" ] && cat \"$sel\"; "
      + "rm -f \"$sel\" \"$done_f\""
    backgroundBrowseProc.command = ["bash", "-c", script]
    backgroundBrowseProc.running = true
  }

  Process {
    id: backgroundBrowseProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text || "").trim()
        if (path) root.applyBackgroundFromFile(path)
      }
    }
  }

  // A browsed file is copied into the theme's user backgrounds dir, which the
  // list above already scans, so it stays selectable (and keeps working as the
  // saved background) if the original is later moved or deleted. Files already
  // inside a scanned dir are used in place. A name clash with different
  // content gets a timestamp prefix instead of overwriting the earlier copy.
  function applyBackgroundFromFile(path) {
    var script = "src=$(realpath -- \"$1\") || exit 1; "
      + "theme=$(cat \"$HOME/.local/state/roseshell/current/theme.name\" 2>/dev/null); "
      + "dir=\"$HOME/.config/roseshell/backgrounds/$theme\"; "
      + "themedir=$(realpath -m \"$HOME/.local/state/roseshell/current/theme/backgrounds\"); "
      + "case \"$src\" in \"$dir\"/*|\"$themedir\"/*) dest=$src ;; "
      + "*) mkdir -p \"$dir\" || exit 1; dest=\"$dir/${src##*/}\"; "
      + "if [ -e \"$dest\" ] && ! cmp -s \"$src\" \"$dest\"; then dest=\"$dir/$(date +%s)-${src##*/}\"; fi; "
      + "[ -e \"$dest\" ] || cp -- \"$src\" \"$dest\" || exit 1 ;; esac; "
      + "roseshell-theme-bg-set \"$dest\" && printf '%s\\n' \"$dest\""
    backgroundImportProc.command = ["bash", "-c", script, "bash", path]
    backgroundImportProc.running = true
  }

  Process {
    id: backgroundImportProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var dest = String(text || "").trim()
        if (dest) root.backgroundValue = dest
        backgroundList.running = true
        backgroundCurrent.running = true
      }
    }
  }

  function applyFont(name) {
    root.fontValue = name
    Util.execDetached("roseshell-font-set " + Util.shellQuote(name))
  }

  function applyCursor(name) {
    root.cursorValue = name
    Util.execDetached(
      "hyprctl setcursor " + Util.shellQuote(name) + " 20"
      + " && gsettings set org.gnome.desktop.interface cursor-theme " + Util.shellQuote(name)
    )
  }

  function applyIcon(name) {
    root.iconValue = name
    Util.execDetached("gsettings set org.gnome.desktop.interface icon-theme " + Util.shellQuote(name))
  }

  // ============================================================ shell

  property bool barTransparent: false
  property bool nightlightEnabled: false
  property bool nightlightLoaded: false

  Process {
    id: shellConfigProbe
    command: ["bash", "-c", "roseshell-shell shell listShellConfig"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseShellConfig(text) }
  }

  property var shellConfig: ({})

  function parseShellConfig(text) {
    try {
      var cfg = JSON.parse(text)
      root.shellConfig = cfg || {}
      root.barTransparent = !!(cfg && cfg.bar && cfg.bar.transparent)
    } catch (e) {}
  }

  // Which of left/center/right a bar-widget id currently sits in, or "" if
  // it isn't placed. listPlugins doesn't carry this -- only the raw config does.
  function barSectionFor(id) {
    var layout = root.shellConfig && root.shellConfig.bar && root.shellConfig.bar.layout
    if (!layout) return ""
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var entries = layout[sections[s]] || []
      for (var i = 0; i < entries.length; i++) {
        if (entries[i] && entries[i].id === id) return sections[s]
      }
    }
    return ""
  }

  function moveBarWidgetToSection(id, section) {
    Util.execDetached("roseshell-shell shell moveBarWidget " + Util.shellQuote(id) + " " + Util.shellQuote(JSON.stringify({ section: section })))
    barConfigRefreshDelay.restart()
  }

  Timer {
    id: barConfigRefreshDelay
    interval: 500
    onTriggered: shellConfigProbe.running = true
  }

  Process {
    id: nightlightProbe
    command: ["bash", "-c", "roseshell-shell nightlight status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseNightlight(text) }
  }

  function parseNightlight(text) {
    try {
      var s = JSON.parse(text)
      root.nightlightEnabled = !!s.enabled
      root.nightlightLoaded = true
    } catch (e) {}
  }

  function toggleBarTransparency() {
    root.barTransparent = !root.barTransparent
    Util.execDetached("roseshell-shell shell toggleBarTransparency")
  }

  function toggleNightlight() {
    root.nightlightEnabled = !root.nightlightEnabled
    Util.execDetached("roseshell-shell nightlight toggle")
  }

  // ============================================================ plugins

  property var pluginList: []
  property string pluginFilter: ""

  readonly property var filteredPlugins: {
    if (!root.pluginFilter) return root.pluginList
    var q = root.pluginFilter.toLowerCase()
    var out = []
    for (var i = 0; i < root.pluginList.length; i++) {
      var p = root.pluginList[i]
      var name = String(p.name || p.id).toLowerCase()
      if (name.indexOf(q) !== -1 || String(p.id).toLowerCase().indexOf(q) !== -1) out.push(p)
    }
    return out
  }

  Process {
    id: pluginListProbe
    command: ["bash", "-c", "roseshell-shell shell listPlugins"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parsePlugins(text) }
  }

  function parsePlugins(text) {
    try {
      root.pluginList = JSON.parse(text)
    } catch (e) {
      root.pluginList = []
    }
  }

  function togglePlugin(id, canDisable, currentlyEnabled) {
    if (canDisable === false) return
    var next = !currentlyEnabled
    var list = root.pluginList.slice()
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === id) {
        list[i] = {
          id: list[i].id, name: list[i].name, kinds: list[i].kinds,
          enabled: next, active: list[i].active, canDisable: list[i].canDisable,
          firstParty: list[i].firstParty, clonedFrom: list[i].clonedFrom
        }
      }
    }
    root.pluginList = list
    Util.execDetached("roseshell-shell shell setPluginEnabled " + Util.shellQuote(id) + " " + (next ? "true" : "false"))
    pluginRefreshDelay.restart()
  }

  Timer {
    id: pluginRefreshDelay
    interval: 700
    onTriggered: pluginListProbe.running = true
  }

  // Deletion is a real `rm -rf` of the plugin's directory (via roseshell-plugin
  // remove), only possible for community plugins installed under
  // ~/.config/roseshell/plugins/<id> -- first-party ones (firstParty: true)
  // never show the trash icon at all, so this never targets shell/plugins/*.
  property string pendingDeleteId: ""
  property string pendingDeleteName: ""
  readonly property bool confirmDeleteOpen: root.pendingDeleteId !== ""

  function requestDeletePlugin(id, name) {
    root.pendingDeleteId = id
    root.pendingDeleteName = name || id
  }

  function cancelDeletePlugin() {
    root.pendingDeleteId = ""
    root.pendingDeleteName = ""
  }

  function confirmDeletePlugin() {
    var id = root.pendingDeleteId
    root.pendingDeleteId = ""
    root.pendingDeleteName = ""
    if (!id) return
    Util.execDetached("roseshell-plugin remove " + Util.shellQuote(id))
    pluginRefreshDelay.restart()
  }

  // ============================================================ view

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "roseshell-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: Math.min(root.cardMaxHeight, content.implicitHeight + Style.spacing.panelPadding * 2)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.confirmDeleteOpen) root.cancelDeletePlugin()
            else root.dismiss()
            event.accepted = true
          }
        }
      }

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.spacing.lg

        Text {
          textFormat: Text.PlainText
          text: "Settings"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        Row {
          width: parent.width
          spacing: Style.spacing.md

          Repeater {
            model: [
              { id: "appearance", label: "Appearance" },
              { id: "shell", label: "Shell" },
              { id: "plugins", label: "Plugins" }
            ]

            delegate: Text {
              required property var modelData
              textFormat: Text.PlainText
              text: modelData.label
              color: root.activeTab === modelData.id ? root.foreground : Qt.darker(root.foreground, 1.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: root.activeTab === modelData.id

              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.spacing.xs
                cursorShape: Qt.PointingHandCursor
                onClicked: root.activeTab = modelData.id
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Util.alpha(root.foreground, 0.12)
        }

        // ---------------------------------------------------- appearance tab

        Column {
          width: parent.width
          spacing: Style.spacing.lg
          visible: root.activeTab === "appearance"

          SearchableDropdown {
            width: parent.width
            label: "Theme"
            value: root.themeValue
            options: root.themeOptions
            placeholderText: "Search themes..."
            onChanged: function(v) { root.applyTheme(v) }
          }

          Column {
            width: parent.width
            spacing: Style.spacing.xs

            SearchableDropdown {
              width: parent.width
              label: "Background"
              value: root.backgroundValue
              options: root.backgroundOptions
              placeholderText: "Search backgrounds..."
              emptyText: "No backgrounds for this theme"
              onChanged: function(v) { root.applyBackground(v) }
            }

            Button {
              text: backgroundBrowseProc.running ? "Browsing..." : "Browse for image..."
              bordered: true
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              enabled: !backgroundBrowseProc.running
              onClicked: root.browseForBackground()
            }

            Button {
              text: matchThemeProc.running ? "Matching..." : "Match theme colors to background"
              bordered: true
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              enabled: !matchThemeProc.running && root.backgroundValue !== ""
              onClicked: root.matchThemeToBackground()
            }
          }

          SearchableDropdown {
            width: parent.width
            label: "Font"
            value: root.fontValue
            options: root.fontOptions
            placeholderText: "Search fonts..."
            onChanged: function(v) { root.applyFont(v) }
          }

          SearchableDropdown {
            width: parent.width
            label: "Cursor"
            value: root.cursorValue
            options: root.cursorOptions
            placeholderText: "Search cursor themes..."
            onChanged: function(v) { root.applyCursor(v) }
          }

          SearchableDropdown {
            width: parent.width
            label: "Icons"
            value: root.iconValue
            options: root.iconOptions
            placeholderText: "Search icon themes..."
            onChanged: function(v) { root.applyIcon(v) }
          }
        }

        // ---------------------------------------------------- shell tab

        Column {
          width: parent.width
          spacing: Style.spacing.md
          visible: root.activeTab === "shell"

          Row {
            width: parent.width
            height: Style.spacing.controlHeight

            Text {
              textFormat: Text.PlainText
              text: "Bar transparency"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - toggleTransparent.width
            }

            ToggleSwitch {
              id: toggleTransparent
              anchors.verticalCenter: parent.verticalCenter
              checked: root.barTransparent
              onToggled: root.toggleBarTransparency()
            }
          }

          Row {
            width: parent.width
            height: Style.spacing.controlHeight

            Text {
              textFormat: Text.PlainText
              text: "Night light"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - toggleNightlight.width
            }

            ToggleSwitch {
              id: toggleNightlight
              anchors.verticalCenter: parent.verticalCenter
              checked: root.nightlightEnabled
              busy: !root.nightlightLoaded
              onToggled: root.toggleNightlight()
            }
          }
        }

        // ---------------------------------------------------- plugins tab

        Column {
          width: parent.width
          spacing: Style.spacing.sm
          visible: root.activeTab === "plugins"

          TextField {
            width: parent.width
            placeholderText: "Search plugins..."
            text: root.pluginFilter
            foreground: root.foreground
            accent: Color.accent
            onTextChanged: root.pluginFilter = text
          }

          Text {
            textFormat: Text.PlainText
            visible: root.filteredPlugins.length === 0
            text: "No plugins found"
            color: Qt.darker(root.foreground, 1.6)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          ListView {
            width: parent.width
            height: Math.min(root.filteredPlugins.length * Style.spacing.controlHeight,
                              Style.spacing.controlHeight * 8)
            clip: true
            model: root.filteredPlugins
            boundsBehavior: Flickable.StopAtBounds

            delegate: Row {
              id: pluginRow
              required property var modelData
              // Aliased once so the bar-section Repeater's own `modelData`
              // (the L/C/R items) doesn't shadow this row's plugin entry.
              readonly property var plugin: modelData
              readonly property bool isBarWidget: Array.isArray(plugin.kinds) && plugin.kinds.indexOf("bar-widget") !== -1
              readonly property bool canDelete: plugin.firstParty === false

              width: ListView.view.width
              height: Style.spacing.controlHeight
              spacing: Style.spacing.sm

              Text {
                textFormat: Text.PlainText
                text: pluginRow.plugin.name || pluginRow.plugin.id
                color: pluginRow.plugin.canDisable === false ? Qt.darker(root.foreground, 1.5) : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - sectionPicker.width - trash.width - rowToggle.width - parent.spacing * 3
              }

              Row {
                id: sectionPicker
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xxs
                visible: pluginRow.isBarWidget && pluginRow.plugin.enabled
                width: visible ? implicitWidth : 0

                Repeater {
                  model: [
                    { key: "left", label: "L" },
                    { key: "center", label: "C" },
                    { key: "right", label: "R" }
                  ]

                  delegate: Text {
                    required property var modelData
                    textFormat: Text.PlainText
                    text: modelData.label
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: root.barSectionFor(pluginRow.plugin.id) === modelData.key
                    color: root.barSectionFor(pluginRow.plugin.id) === modelData.key
                      ? Color.accent : Qt.darker(root.foreground, 1.6)

                    MouseArea {
                      anchors.fill: parent
                      anchors.margins: -Style.spacing.xxs
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.moveBarWidgetToSection(pluginRow.plugin.id, modelData.key)
                    }
                  }
                }
              }

              Text {
                id: trash
                textFormat: Text.PlainText
                text: ""
                visible: pluginRow.canDelete
                width: visible ? implicitWidth : 0
                color: "#e06c75"
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -Style.spacing.xs
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.requestDeletePlugin(pluginRow.plugin.id, pluginRow.plugin.name || pluginRow.plugin.id)
                }
              }

              ToggleSwitch {
                id: rowToggle
                anchors.verticalCenter: parent.verticalCenter
                checked: pluginRow.plugin.enabled
                interactive: pluginRow.plugin.canDisable !== false
                onToggled: root.togglePlugin(pluginRow.plugin.id, pluginRow.plugin.canDisable, pluginRow.plugin.enabled)
              }
            }
          }
        }
      }

      // Delete confirmation. Drawn last so it sits on top of everything else
      // in the card; its own MouseArea eats clicks so they don't fall through
      // to the plugin list underneath.
      Item {
        anchors.fill: parent
        visible: root.confirmDeleteOpen

        MouseArea {
          anchors.fill: parent
          onClicked: {}
        }

        Rectangle {
          anchors.fill: parent
          radius: root.cornerRadius
          color: Qt.rgba(0, 0, 0, 0.55)
        }

        BorderSurface {
          width: Math.min(Style.space(320), parent.width - Style.spacing.xl)
          height: confirmContent.implicitHeight + Style.spacing.panelPadding * 2
          radius: root.cornerRadius
          anchors.centerIn: parent
          color: root.background
          borderSpec: root.borderSpec
          padding: Style.spacing.panelPadding

          Column {
            id: confirmContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.lg

            Text {
              textFormat: Text.PlainText
              text: "Delete “" + root.pendingDeleteName + "”?"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              wrapMode: Text.WordWrap
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: "This removes the plugin's files from disk. It can't be undone."
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              width: parent.width
            }

            Row {
              anchors.right: parent.right
              spacing: Style.spacing.md

              Button {
                text: "Cancel"
                bordered: true
                foreground: root.foreground
                accent: Color.accent
                fontFamily: root.fontFamily
                onClicked: root.cancelDeletePlugin()
              }

              Button {
                text: "Delete"
                bordered: true
                foreground: "#e06c75"
                accent: "#e06c75"
                fontFamily: root.fontFamily
                onClicked: root.confirmDeletePlugin()
              }
            }
          }
        }
      }
    }
  }
}
