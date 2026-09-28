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
  // Switches and segmented controls go pill-shaped only when the theme rounds
  // its corners, the same rule the shared ToggleSwitch follows.
  readonly property bool pillShapes: Style.cornerRadius > 0
  property string fontFamily: Style.font.menuFamily
  property int cardWidth: Math.min(Style.space(560), panel.width - Style.gapsOut * 2)
  property int cardMaxHeight: Math.max(Style.space(300), panel.height - Style.gapsOut * 6)

  property string activeTab: "appearance" // appearance | shell | plugins

  function open(payloadJson) {
    root.opened = true
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    root.activeTab = ["appearance", "shell", "plugins"].indexOf(payload.tab) !== -1 ? payload.tab : "appearance"
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
    colorsFile.reload()
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

  // The active theme's palette, read straight from colors.toml so the swatches
  // show exactly what the theme wrote. Reloaded on open and after any theme
  // change; the theme dir is swapped wholesale, so a file watch wouldn't hold.
  property var paletteColors: ({})
  property string themeMode: ""
  property string hoveredSwatch: ""

  FileView {
    id: colorsFile
    path: Quickshell.env("HOME") + "/.local/state/roseshell/current/theme/colors.toml"
    printErrors: false
    onLoaded: root.parsePalette(text())
  }

  function parsePalette(raw) {
    var out = {}
    var mode = ""
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*([A-Za-z0-9_]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (m) out[m[1]] = m[2]
      var mm = lines[i].match(/^\s*mode\s*=\s*["'](\w+)["']/)
      if (mm) mode = mm[1]
    }
    root.paletteColors = out
    root.themeMode = mode
  }

  // Swatch rows: surfaces and text first, then the terminal colors. Older
  // themes only carry color0..color15, so those stand in when names are absent.
  function paletteRow(keys, fallbackKeys) {
    var row = []
    var list = keys
    var found = 0
    for (var i = 0; i < keys.length; i++) if (root.paletteColors[keys[i]]) found++
    if (found < 3 && fallbackKeys) list = fallbackKeys
    for (var j = 0; j < list.length; j++) {
      var c = root.paletteColors[list[j]]
      if (c) row.push({ key: list[j], color: c })
    }
    return row
  }

  readonly property var paletteRows: [
    root.paletteRow(["darker_background", "background", "lighter_background", "selection", "muted", "dark_foreground", "foreground", "bright_foreground", "accent"],
                    ["color0", "background", "color8", "color7", "foreground", "color15", "accent"]),
    root.paletteRow(["red", "orange", "yellow", "green", "cyan", "blue", "magenta", "brown"],
                    ["color1", "color3", "color2", "color6", "color4", "color5"]),
    root.paletteRow(["bright_red", "bright_yellow", "bright_green", "bright_cyan", "bright_blue", "bright_magenta"],
                    ["color9", "color11", "color10", "color14", "color12", "color13"])
  ]

  function prettyKey(key) {
    return String(key || "").replace(/_/g, " ")
  }

  function prettyTheme(name) {
    return String(name || "").replace(/-/g, " ").replace(/\b\w/g, function(c) { return c.toUpperCase() })
  }

  function copySwatch(hex) {
    Util.execDetached("printf %s " + Util.shellQuote(hex) + " | wl-copy")
    root.hoveredSwatch = "Copied " + hex
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
      colorsFile.reload()
    }
  }

  Timer {
    id: backgroundRefreshDelay
    interval: 1200
    onTriggered: {
      backgroundList.running = true
      backgroundCurrent.running = true
      colorsFile.reload()
    }
  }

  // Asks the desktop's file chooser portal for an image, which opens the
  // default file manager's own picker. This overlay sits above every window
  // and holds the keyboard, so it steps aside while the picker is up and comes
  // back once a file is chosen or the picker is cancelled.
  function browseForBackground() {
    var start = Quickshell.env("HOME") + "/Pictures"
    backgroundBrowseProc.command = ["roseshell-pick-file", "--images", "--title", "Choose a background", "--folder", start]
    backgroundBrowseProc.running = true
    root.dismiss()
  }

  Process {
    id: backgroundBrowseProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text || "").trim()
        if (path) root.applyBackgroundFromFile(path)
        if (root.shell && typeof root.shell.summon === "function")
          root.shell.summon((root.manifest && root.manifest.id) || "roseshell.settings", "{}")
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
  property real glassTint: 0
  property bool glassBlur: false
  property int glassBlurSize: 8
  property int glassBlurPasses: 2

  property bool nightlightEnabled: false
  property bool nightlightLoaded: false
  property int nightTemperature: 4000
  property string nightSchedule: "manual"
  property string nightStart: "20:00"
  property string nightEnd: "07:00"
  property string nightSunset: ""
  property string nightSunrise: ""
  property string nightZone: ""

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
      var bar = (cfg && cfg.bar) || {}
      root.barTransparent = !!bar.transparent
      var glass = bar.glass || {}
      root.glassTint = Math.max(0, Math.min(1, Number(glass.tint) || 0))
      root.glassBlur = glass.blur === true
      root.glassBlurSize = Number(glass.blurSize) > 0 ? Math.round(glass.blurSize) : 8
      root.glassBlurPasses = Number(glass.blurPasses) > 0 ? Math.round(glass.blurPasses) : 2
    } catch (e) {}
  }

  // Writes one shell.json value in-process (the same path the bar's own
  // context menu uses) and mirrors it into the local copy.
  function setConfigValue(keys, value) {
    if (!root.shell || typeof root.shell.mutateShellConfig !== "function") return
    root.shell.mutateShellConfig(function(config) {
      var node = config
      for (var i = 0; i < keys.length - 1; i++) {
        if (!node[keys[i]] || typeof node[keys[i]] !== "object") node[keys[i]] = {}
        node = node[keys[i]]
      }
      node[keys[keys.length - 1]] = value
    })
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
      if (s.nightTemperature) root.nightTemperature = s.nightTemperature
      if (s.schedule) root.nightSchedule = s.schedule
      if (s.start) root.nightStart = s.start
      if (s.end) root.nightEnd = s.end
      root.nightSunset = s.sunset || ""
      root.nightSunrise = s.sunrise || ""
      root.nightZone = s.zone || ""
      root.nightlightLoaded = true
    } catch (e) {}
  }

  Timer {
    id: nightlightRefreshDelay
    interval: 400
    onTriggered: nightlightProbe.running = true
  }

  function toggleBarTransparency() {
    root.barTransparent = !root.barTransparent
    Util.execDetached("roseshell-shell shell toggleBarTransparency")
    root.applyBlur()
  }

  function setGlassTint(value) {
    root.glassTint = value
    root.setConfigValue(["bar", "glass", "tint"], Math.round(value * 100) / 100)
  }

  function setGlassBlur(enabled, size, passes) {
    root.glassBlur = enabled
    root.glassBlurSize = size
    root.glassBlurPasses = passes
    root.setConfigValue(["bar", "glass"], {
      tint: Math.round(root.glassTint * 100) / 100,
      blur: enabled, blurSize: size, blurPasses: passes
    })
    root.applyBlur()
  }

  // Hyprland blur only matters behind a see-through bar, so it follows both
  // switches: transparency and blur.
  function applyBlur() {
    var on = root.barTransparent && root.glassBlur
    Util.execDetached("roseshell-bar-blur " + (on ? "on" : "off") + " " + root.glassBlurSize + " " + root.glassBlurPasses)
  }

  function toggleNightlight() {
    root.nightlightEnabled = !root.nightlightEnabled
    Util.execDetached("roseshell-shell nightlight toggle")
  }

  // The slider previews while dragging and saves on release; the service
  // re-applies a saved temperature on its own while night light is on.
  function previewNightTemperature(value) {
    root.nightTemperature = value
    if (root.nightlightEnabled) Util.execDetached("roseshell-shell -q nightlight preview " + Math.round(value))
  }

  function setNightTemperature(value) {
    root.nightTemperature = Math.round(value)
    root.setConfigValue(["nightlight", "temperature"], root.nightTemperature)
  }

  function setNightSchedule(mode) {
    root.nightSchedule = mode
    root.setConfigValue(["nightlight", "schedule"], mode)
    nightlightRefreshDelay.restart()
  }

  function setNightTime(key, value) {
    if (key === "start") root.nightStart = value
    else root.nightEnd = value
    root.setConfigValue(["nightlight", key], value)
    nightlightRefreshDelay.restart()
  }

  // "20:30" -> "8:30 PM", matching the bar clock's 12-hour format.
  function prettyTime(hhmm) {
    var parts = String(hhmm || "").split(":")
    if (parts.length !== 2) return ""
    var h = Number(parts[0])
    var suffix = h >= 12 ? "PM" : "AM"
    var h12 = h % 12 === 0 ? 12 : h % 12
    return h12 + ":" + parts[1] + " " + suffix
  }

  readonly property var timeOptions: {
    var out = []
    for (var m = 0; m < 1440; m += 15) {
      var h = Math.floor(m / 60)
      var mm = m % 60
      var value = (h < 10 ? "0" : "") + h + ":" + (mm < 10 ? "0" : "") + mm
      out.push({ value: value, label: root.prettyTime(value) })
    }
    return out
  }

  // Warmth as a percentage: 5500K is the gentlest night light, 2500K the warmest.
  function warmthPercent(temp) {
    return Math.round((5500 - temp) / 3000 * 100)
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

  // ============================================================ components

  // Pill switch: accent track when on, so state reads at a glance whatever the
  // theme's corner style.
  component PillSwitch: Item {
    id: sw
    property bool checked: false
    property bool busy: false
    property bool interactive: true
    signal toggled()

    implicitWidth: Style.space(40)
    implicitHeight: Style.space(22)
    opacity: interactive ? 1 : 0.4

    Rectangle {
      id: swTrack
      anchors.fill: parent
      radius: root.pillShapes ? height / 2 : 0
      color: sw.checked ? Color.accent : Util.alpha(root.foreground, 0.12)
      border.width: 1
      border.color: sw.checked ? Color.accent : Util.alpha(root.foreground, swMouse.containsMouse && sw.interactive ? 0.4 : 0.22)

      Behavior on color { ColorAnimation { duration: 140 } }

      Rectangle {
        width: swTrack.height - Style.space(6)
        height: width
        radius: root.pillShapes ? width / 2 : 0
        anchors.verticalCenter: parent.verticalCenter
        x: sw.checked ? swTrack.width - width - Style.space(3) : Style.space(3)
        color: sw.checked ? root.background : Qt.darker(root.foreground, 1.15)

        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
      }
    }

    MouseArea {
      id: swMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: sw.interactive
      cursorShape: Qt.PointingHandCursor
      onClicked: if (!sw.busy) sw.toggled()
    }
  }

  // A softly raised group of related settings.
  component SettingsCard: Rectangle {
    default property alias content: cardColumn.data
    property int contentSpacing: Style.spacing.xl

    width: parent ? parent.width : 0
    height: cardColumn.implicitHeight + Style.spacing.xl * 2
    radius: Style.cornerRadius
    color: Util.alpha(root.foreground, 0.035)
    border.width: 1
    border.color: Util.alpha(root.foreground, 0.1)

    Column {
      id: cardColumn
      x: Style.spacing.xl
      y: Style.spacing.xl
      width: parent.width - Style.spacing.xl * 2
      spacing: parent.contentSpacing
    }
  }

  // Icon, title and optional subtitle on the left, a control on the right.
  component SettingRow: Item {
    id: settingRow
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    default property alias trailing: trailingSlot.data

    width: parent ? parent.width : 0
    height: Math.max(Style.space(30), rowText.implicitHeight)

    Text {
      id: rowIcon
      visible: settingRow.icon !== ""
      width: visible ? Style.space(24) : 0
      anchors.verticalCenter: parent.verticalCenter
      text: settingRow.icon
      color: Color.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.iconLarge
      horizontalAlignment: Text.AlignHCenter
    }

    Column {
      id: rowText
      anchors.left: rowIcon.right
      anchors.leftMargin: settingRow.icon !== "" ? Style.spacing.xl : 0
      anchors.right: trailingSlot.left
      anchors.rightMargin: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xxs

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: settingRow.title
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: settingRow.subtitle !== ""
        textFormat: Text.PlainText
        text: settingRow.subtitle
        color: Qt.darker(root.foreground, 1.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Item {
      id: trailingSlot
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: childrenRect.width
      height: childrenRect.height
    }
  }

  // Caption on the left, current value on the right, slider underneath.
  component LabeledSlider: Column {
    id: labeledSlider
    property string label: ""
    property string valueText: ""
    property string minLabel: ""
    property string maxLabel: ""
    property alias value: sliderControl.value
    property alias minimum: sliderControl.minimum
    property alias maximum: sliderControl.maximum
    property alias integer: sliderControl.integer
    property alias tickCount: sliderControl.tickCount
    signal moved(real value)
    signal released(real value)

    width: parent ? parent.width : 0
    spacing: Style.spacing.xs

    Item {
      width: parent.width
      height: sliderLabel.implicitHeight

      Text {
        id: sliderLabel
        textFormat: Text.PlainText
        text: labeledSlider.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: labeledSlider.valueText
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    PanelSlider {
      id: sliderControl
      width: parent.width
      trackColor: Util.alpha(root.foreground, 0.14)
      fillColor: Color.accent
      knobColor: root.foreground
      tickColor: root.background
      onMoved: function(v) { labeledSlider.moved(v) }
      onReleased: function(v) { labeledSlider.released(v) }
    }

    Item {
      width: parent.width
      height: minText.implicitHeight
      visible: labeledSlider.minLabel !== "" || labeledSlider.maxLabel !== ""

      Text {
        id: minText
        textFormat: Text.PlainText
        text: labeledSlider.minLabel
        color: Qt.darker(root.foreground, 1.7)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: labeledSlider.maxLabel
        color: Qt.darker(root.foreground, 1.7)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // A ListView delegate's modelData hands nested arrays over as Qt lists,
  // which Array.isArray rejects, so copy them out element by element.
  function pluginKinds(plugin) {
    var kinds = plugin ? plugin.kinds : null
    var out = []
    if (kinds && kinds.length !== undefined)
      for (var i = 0; i < kinds.length; i++) out.push(String(kinds[i]))
    return out
  }

  function pluginKindLabel(plugin) {
    var names = { "bar-widget": "Bar widget", "panel": "Panel", "service": "Service", "overlay": "Overlay", "menu": "Menu", "bar": "Bar" }
    var kinds = root.pluginKinds(plugin)
    var out = []
    for (var i = 0; i < kinds.length; i++) out.push(names[kinds[i]] || kinds[i])
    out.push(plugin.firstParty === false ? "Community" : "Built-in")
    return out.join(" · ")
  }

  function pluginIcon(plugin) {
    var kinds = root.pluginKinds(plugin)
    if (kinds.indexOf("bar-widget") !== -1) return "󰕮"
    if (kinds.indexOf("service") !== -1) return "󰒓"
    if (kinds.indexOf("menu") !== -1) return "󰍜"
    if (kinds.indexOf("bar") !== -1) return "󰍹"
    return "󰏗"
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
          spacing: Style.spacing.sm

          Repeater {
            model: [
              { id: "appearance", label: "Appearance", icon: "󰏘" },
              { id: "shell", label: "Shell", icon: "󰍹" },
              { id: "plugins", label: "Plugins", icon: "󰐱" }
            ]

            delegate: Button {
              required property var modelData
              text: modelData.label
              iconText: modelData.icon
              selected: root.activeTab === modelData.id
              bordered: root.activeTab === modelData.id
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              onClicked: root.activeTab = modelData.id
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ---------------------------------------------------- appearance tab

        Column {
          width: parent.width
          spacing: Style.spacing.xl
          visible: root.activeTab === "appearance"

          // Theme: picker plus the palette it applies.
          Column {
            width: parent.width
            spacing: Style.spacing.md

            Row {
              width: parent.width

              PanelSectionHeader {
                text: "THEME"
                foreground: root.foreground
                fontFamily: root.fontFamily
                width: parent.width - modeLabel.width
              }

              Text {
                id: modeLabel
                textFormat: Text.PlainText
                text: root.themeMode ? root.prettyTheme(root.themeMode) + " mode" : ""
                color: Qt.darker(root.foreground, 1.6)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.bottom: parent.bottom
              }
            }

            SearchableDropdown {
              width: parent.width
              showLabel: false
              value: root.themeValue
              options: root.themeOptions
              placeholderText: "Search themes..."
              onChanged: function(v) { root.applyTheme(v) }
            }

            // Palette swatches. Each row stretches its swatches to the full
            // width; hover names a color, click copies its hex.
            Column {
              width: parent.width
              spacing: Style.spacing.sm

              Repeater {
                model: root.paletteRows

                delegate: Row {
                  id: swatchRow
                  required property var modelData
                  required property int index
                  readonly property int gap: Style.spacing.sm
                  width: parent.width
                  spacing: gap
                  visible: modelData.length > 0

                  Repeater {
                    model: swatchRow.modelData

                    delegate: Rectangle {
                      required property var modelData
                      width: (swatchRow.width - swatchRow.gap * (swatchRow.modelData.length - 1)) / swatchRow.modelData.length
                      height: swatchRow.index === 0 ? Style.space(34) : Style.space(22)
                      radius: Style.cornerRadius
                      color: modelData.color
                      border.width: swatchHover.hovered ? 2 : 1
                      border.color: swatchHover.hovered ? root.foreground : Util.alpha(root.foreground, 0.15)

                      HoverHandler {
                        id: swatchHover
                        onHoveredChanged: {
                          if (hovered) root.hoveredSwatch = root.prettyKey(modelData.key) + "  " + modelData.color
                          else if (root.hoveredSwatch.indexOf(modelData.color) !== -1) root.hoveredSwatch = ""
                        }
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.copySwatch(modelData.color)
                      }
                    }
                  }
                }
              }

              Text {
                textFormat: Text.PlainText
                text: root.hoveredSwatch || "Hover a color to see its value, click to copy"
                color: root.hoveredSwatch ? root.foreground : Qt.darker(root.foreground, 1.6)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          // Background: live preview beside its picker and actions.
          Column {
            width: parent.width
            spacing: Style.spacing.md

            PanelSectionHeader {
              text: "BACKGROUND"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              width: parent.width
              spacing: Style.spacing.xl

              Rectangle {
                id: bgPreview
                width: Style.space(176)
                height: Math.round(width * 9 / 16)
                radius: Style.cornerRadius
                color: Util.alpha(root.foreground, 0.06)
                border.width: 1
                border.color: Util.alpha(root.foreground, 0.15)
                clip: true

                readonly property bool isVideo: Util.isVideoPath(root.backgroundValue)

                Image {
                  anchors.fill: parent
                  anchors.margins: 1
                  visible: !bgPreview.isVideo
                  source: root.backgroundValue && !bgPreview.isVideo ? Util.fileUrl(root.backgroundValue) : ""
                  sourceSize.width: width * 2
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: false
                }

                Text {
                  anchors.centerIn: parent
                  visible: bgPreview.isVideo || !root.backgroundValue
                  text: bgPreview.isVideo ? "󰕧" : "󰋩"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.displayLarge
                }
              }

              Column {
                width: parent.width - bgPreview.width - parent.spacing
                spacing: Style.spacing.md

                SearchableDropdown {
                  width: parent.width
                  showLabel: false
                  value: root.backgroundValue
                  options: root.backgroundOptions
                  placeholderText: "Search backgrounds..."
                  emptyText: "No backgrounds for this theme"
                  onChanged: function(v) { root.applyBackground(v) }
                }

                Button {
                  width: parent.width
                  leftAlign: true
                  iconText: "󰉋"
                  text: backgroundBrowseProc.running ? "Choosing..." : "Choose from files..."
                  bordered: true
                  foreground: root.foreground
                  accent: Color.accent
                  fontFamily: root.fontFamily
                  enabled: !backgroundBrowseProc.running
                  onClicked: root.browseForBackground()
                }

                Button {
                  width: parent.width
                  leftAlign: true
                  iconText: "󰸉"
                  text: matchThemeProc.running ? "Matching..." : "Match theme colors to background"
                  bordered: true
                  foreground: root.foreground
                  accent: Color.accent
                  fontFamily: root.fontFamily
                  enabled: !matchThemeProc.running && root.backgroundValue !== ""
                  onClicked: root.matchThemeToBackground()
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          // Style: label on the left, picker on the right.
          Column {
            width: parent.width
            spacing: Style.spacing.md

            PanelSectionHeader {
              text: "STYLE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: [
                { label: "Font", icon: "󰛖", key: "font", placeholder: "Search fonts..." },
                { label: "Cursor", icon: "󰇀", key: "cursor", placeholder: "Search cursor themes..." },
                { label: "Icons", icon: "󰀻", key: "icon", placeholder: "Search icon themes..." }
              ]

              delegate: Row {
                required property var modelData
                width: parent.width
                height: Style.spacing.controlHeight
                spacing: Style.spacing.md

                Text {
                  width: Style.space(20)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.icon
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.icon
                  horizontalAlignment: Text.AlignHCenter
                }

                Text {
                  id: styleLabel
                  width: Style.space(70)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: modelData.label
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                SearchableDropdown {
                  width: parent.width - Style.space(20) - styleLabel.width - parent.spacing * 2
                  anchors.verticalCenter: parent.verticalCenter
                  showLabel: false
                  value: modelData.key === "font" ? root.fontValue : modelData.key === "cursor" ? root.cursorValue : root.iconValue
                  options: modelData.key === "font" ? root.fontOptions : modelData.key === "cursor" ? root.cursorOptions : root.iconOptions
                  placeholderText: modelData.placeholder
                  onChanged: function(v) {
                    if (modelData.key === "font") root.applyFont(v)
                    else if (modelData.key === "cursor") root.applyCursor(v)
                    else root.applyIcon(v)
                  }
                }
              }
            }
          }
        }

        // ---------------------------------------------------- shell tab

        Column {
          width: parent.width
          spacing: Style.spacing.md
          visible: root.activeTab === "shell"

          PanelSectionHeader {
            text: "NIGHT LIGHT"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          SettingsCard {
            SettingRow {
              icon: root.nightlightEnabled ? "󰖔" : "󰖙"
              title: "Night light"
              subtitle: {
                if (root.nightSchedule === "sunset" && root.nightSunset)
                  return "On from sunset (" + root.prettyTime(root.nightSunset) + ") to sunrise (" + root.prettyTime(root.nightSunrise) + ")"
                if (root.nightSchedule === "custom")
                  return "On from " + root.prettyTime(root.nightStart) + " to " + root.prettyTime(root.nightEnd)
                return root.nightlightEnabled ? "On until you turn it off" : "Warms the screen to ease eye strain"
              }

              PillSwitch {
                checked: root.nightlightEnabled
                busy: !root.nightlightLoaded
                onToggled: root.toggleNightlight()
              }
            }

            LabeledSlider {
              label: "Warmth"
              valueText: root.warmthPercent(root.nightTemperature) + "%  ·  " + root.nightTemperature + "K"
              minLabel: "Subtle"
              maxLabel: "Warm"
              // Reversed so dragging right means warmer (a lower temperature).
              minimum: 2500
              maximum: 5500
              integer: true
              value: 8000 - root.nightTemperature
              onMoved: function(v) { root.previewNightTemperature(8000 - Math.round(v / 50) * 50) }
              onReleased: function(v) { root.setNightTemperature(8000 - Math.round(v / 50) * 50) }
            }

            PanelSeparator { foreground: root.foreground; strength: 0.08 }

            Column {
              width: parent.width
              spacing: Style.spacing.md

              Text {
                textFormat: Text.PlainText
                text: "Schedule"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              ButtonGroup {
                value: root.nightSchedule
                foreground: root.foreground
                accent: Color.accent
                fontFamily: root.fontFamily
                options: [
                  { value: "manual", label: "Off", icon: "󰜺" },
                  { value: "sunset", label: "Sunset to sunrise", icon: "󰖛" },
                  { value: "custom", label: "Custom", icon: "󰥔" }
                ]
                onChanged: function(v) { root.setNightSchedule(v) }
              }

              Row {
                width: parent.width
                spacing: Style.spacing.lg
                visible: root.nightSchedule === "custom"

                Repeater {
                  model: [
                    { key: "start", label: "From" },
                    { key: "end", label: "To" }
                  ]

                  delegate: Row {
                    required property var modelData
                    width: (parent.width - Style.spacing.lg) / 2
                    spacing: Style.spacing.md

                    Text {
                      id: timeLabel
                      width: Style.space(34)
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: modelData.label
                      color: Qt.darker(root.foreground, 1.4)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }

                    SearchableDropdown {
                      width: parent.width - timeLabel.width - parent.spacing
                      showLabel: false
                      value: modelData.key === "start" ? root.nightStart : root.nightEnd
                      options: root.timeOptions
                      placeholderText: "Search times..."
                      onChanged: function(v) { root.setNightTime(modelData.key, v) }
                    }
                  }
                }
              }

              Text {
                width: parent.width
                visible: root.nightSchedule === "sunset"
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: root.nightSunset
                  ? "Today: sunset " + root.prettyTime(root.nightSunset) + ", sunrise " + root.prettyTime(root.nightSunrise)
                    + (root.nightZone ? "  ·  from your timezone (" + root.nightZone + ")" : "")
                  : "Couldn't work out sun times from the system timezone."
                color: Qt.darker(root.foreground, 1.6)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Item { width: 1; height: Style.spacing.md }

          PanelSectionHeader {
            text: "MENU BAR"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          SettingsCard {
            SettingRow {
              icon: "󰖲"
              title: "Transparent bar"
              subtitle: "Let the background show through the bar"

              PillSwitch {
                checked: root.barTransparent
                onToggled: root.toggleBarTransparency()
              }
            }

            LabeledSlider {
              visible: root.barTransparent
              label: "Tint"
              valueText: Math.round(root.glassTint * 100) + "%"
              minLabel: "Clear"
              maxLabel: "Solid"
              minimum: 0
              maximum: 100
              integer: true
              value: Math.round(root.glassTint * 100)
              onReleased: function(v) { root.setGlassTint(v / 100) }
            }

            SettingRow {
              visible: root.barTransparent
              icon: "󰂵"
              title: "Blur"
              subtitle: "Frost whatever sits behind the bar"

              PillSwitch {
                checked: root.glassBlur
                onToggled: root.setGlassBlur(!root.glassBlur, root.glassBlurSize, root.glassBlurPasses)
              }
            }

            LabeledSlider {
              visible: root.barTransparent && root.glassBlur
              label: "Blur strength"
              valueText: String(root.glassBlurSize)
              minLabel: "Light"
              maxLabel: "Heavy"
              minimum: 1
              maximum: 20
              integer: true
              value: root.glassBlurSize
              onReleased: function(v) { root.setGlassBlur(true, Math.round(v), root.glassBlurPasses) }
            }

            LabeledSlider {
              visible: root.barTransparent && root.glassBlur
              label: "Blur smoothness"
              valueText: root.glassBlurPasses + (root.glassBlurPasses === 1 ? " pass" : " passes")
              minLabel: "Faster"
              maxLabel: "Smoother"
              minimum: 1
              maximum: 4
              integer: true
              tickCount: 4
              value: root.glassBlurPasses
              onReleased: function(v) { root.setGlassBlur(true, root.glassBlurSize, Math.round(v)) }
            }
          }
        }

        // ---------------------------------------------------- plugins tab

        Column {
          width: parent.width
          spacing: Style.spacing.lg
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

          SettingsCard {
            visible: root.filteredPlugins.length > 0
            contentSpacing: 0

            ListView {
              id: pluginListView
              readonly property int rowHeight: Style.space(46)
              width: parent.width
              height: Math.min(root.filteredPlugins.length, 8) * rowHeight
              clip: true
              model: root.filteredPlugins
              boundsBehavior: Flickable.StopAtBounds

              delegate: Item {
                id: pluginRow
                required property var modelData
                required property int index
                // Aliased once so the section picker's own `modelData`
                // (the L/C/R items) doesn't shadow this row's plugin entry.
                readonly property var plugin: modelData
                readonly property bool isBarWidget: root.pluginKinds(plugin).indexOf("bar-widget") !== -1
                readonly property bool canDelete: plugin.firstParty === false
                readonly property bool locked: plugin.canDisable === false

                width: ListView.view.width
                height: pluginListView.rowHeight

                Rectangle {
                  visible: pluginRow.index > 0
                  width: parent.width
                  height: 1
                  color: Util.alpha(root.foreground, 0.07)
                }

                SettingRow {
                  anchors.verticalCenter: parent.verticalCenter
                  icon: root.pluginIcon(pluginRow.plugin)
                  title: pluginRow.plugin.name || pluginRow.plugin.id
                  subtitle: root.pluginKindLabel(pluginRow.plugin) + (pluginRow.locked ? " · Required" : "")
                  opacity: pluginRow.plugin.enabled ? 1 : 0.6

                  Row {
                    spacing: Style.spacing.lg

                    // Bar placement: a small segmented control.
                    Rectangle {
                      visible: pluginRow.isBarWidget && pluginRow.plugin.enabled
                      anchors.verticalCenter: parent.verticalCenter
                      width: visible ? segRow.width + 2 : 0
                      height: Style.space(22)
                      radius: root.pillShapes ? height / 2 : Style.cornerRadius
                      color: "transparent"
                      border.width: 1
                      border.color: Util.alpha(root.foreground, 0.18)

                      Row {
                        id: segRow
                        x: 1
                        anchors.verticalCenter: parent.verticalCenter

                        Repeater {
                          model: [
                            { key: "left", label: "L" },
                            { key: "center", label: "C" },
                            { key: "right", label: "R" }
                          ]

                          delegate: Rectangle {
                            required property var modelData
                            readonly property bool current: root.barSectionFor(pluginRow.plugin.id) === modelData.key
                            width: Style.space(24)
                            height: Style.space(20)
                            radius: root.pillShapes ? height / 2 : Style.cornerRadius
                            color: current ? Color.accent : (segMouse.containsMouse ? Util.alpha(root.foreground, 0.1) : "transparent")

                            Text {
                              anchors.centerIn: parent
                              textFormat: Text.PlainText
                              text: modelData.label
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              font.bold: parent.current
                              color: parent.current ? root.background : Qt.darker(root.foreground, 1.3)
                            }

                            MouseArea {
                              id: segMouse
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: root.moveBarWidgetToSection(pluginRow.plugin.id, modelData.key)
                            }
                          }
                        }
                      }
                    }

                    Text {
                      visible: pluginRow.canDelete
                      width: visible ? implicitWidth : 0
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: "󰩹"
                      color: trashMouse.containsMouse ? "#e06c75" : Qt.darker(root.foreground, 1.6)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.icon

                      MouseArea {
                        id: trashMouse
                        anchors.fill: parent
                        anchors.margins: -Style.spacing.xs
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.requestDeletePlugin(pluginRow.plugin.id, pluginRow.plugin.name || pluginRow.plugin.id)
                      }
                    }

                    PillSwitch {
                      anchors.verticalCenter: parent.verticalCenter
                      checked: pluginRow.plugin.enabled
                      interactive: !pluginRow.locked
                      onToggled: root.togglePlugin(pluginRow.plugin.id, pluginRow.plugin.canDisable, pluginRow.plugin.enabled)
                    }
                  }
                }
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
