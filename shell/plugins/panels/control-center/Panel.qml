import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Networking
import qs.Commons
import qs.Ui

// GNOME-style quick settings. The bar button groups the network, Bluetooth,
// and volume icons; the popup holds power actions, output/input volume, and
// rows that hand off to the full network, Bluetooth, and display panels.
//
// This plugin owns no audio/network/Bluetooth state of its own. It drives the
// live instances of those plugins (looked up through the bar), so it stays in
// sync with them for free. Keep those plugins in the bar layout with
// `"hidden": true`, placed next to this one, so their panels still exist and
// open under this button.
Panel {
  id: root
  moduleName: "roseshell.control-center"
  ipcTarget: "roseshell.control-center"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function peer(id) {
    if (!bar || typeof bar.findPanelWidget !== "function") return null
    return bar.findPanelWidget(id)
  }

  // Reading moduleSlots makes these re-resolve as bar widgets load/unload.
  readonly property var audio: { var _ = bar ? bar.moduleSlots : null; return peer("roseshell.audio") }
  readonly property var network: { var _ = bar ? bar.moduleSlots : null; return peer("roseshell.network") }
  readonly property var bluetooth: { var _ = bar ? bar.moduleSlots : null; return peer("roseshell.bluetooth") }
  readonly property var display: { var _ = bar ? bar.moduleSlots : null; return peer("crmne.hyprmoncfg") }

  function openPeer(item) {
    if (!item) return
    close()
    Qt.callLater(function() { item.open() })
  }

  // ---------------------------------------------------------------- status
  readonly property string networkIcon: network ? network.icon : ""
  readonly property string bluetoothIcon: bluetooth ? bluetooth.icon : ""
  readonly property bool bluetoothOn: !!(bluetooth && bluetooth.adapter && bluetooth.adapter.enabled)
  readonly property string outputIcon: audio ? audio.outputIcon() : ""
  readonly property string inputIcon: audio ? audio.inputIcon() : ""

  readonly property string networkStatus: {
    if (!network) return "Unavailable"
    if (network.kind === "ethernet") return "Ethernet"
    if (network.kind === "wifi" && network.connectedWifiNetwork) return network.connectedWifiNetwork.name
    if (network.canToggleWifi && !Networking.wifiEnabled) return "Wi-Fi off"
    return "Disconnected"
  }

  readonly property string bluetoothStatus: {
    if (!bluetooth || !bluetooth.adapter) return "Unavailable"
    if (!bluetoothOn) return "Off"
    var connected = bluetooth.connectedDevices || []
    if (connected.length === 0) return "On"
    var names = []
    for (var i = 0; i < connected.length; i++) names.push(bluetooth.deviceLabel(connected[i]))
    return names.join(", ")
  }

  // ---------------------------------------------------------------- power
  // Destructive actions take a second click within confirmWindowMs; the icon
  // turns urgent and its tooltip says what the next click will do.
  readonly property int confirmWindowMs: 3000
  property string confirming: ""
  readonly property var powerActions: [
    { id: "lock",     label: "Lock",      icon: "\udb80\udf3e", command: ["roseshell-system-lock"],   confirm: false },
    { id: "suspend",  label: "Suspend",   icon: "󰒲", command: ["systemctl", "suspend"],     confirm: false },
    { id: "logout",   label: "Log out",   icon: "󰍃", command: ["roseshell-system-logout"], confirm: true },
    { id: "reboot",   label: "Restart",   icon: "󰜉", command: ["systemctl", "reboot"],      confirm: true },
    { id: "shutdown", label: "Shut down", icon: "\udb81\udc25", command: ["systemctl", "poweroff"],    confirm: true }
  ]

  function triggerPower(action) {
    if (action.confirm && confirming !== action.id) {
      confirming = action.id
      confirmTimer.restart()
      return
    }
    confirming = ""
    close()
    Quickshell.execDetached(action.command)
  }

  Timer {
    id: confirmTimer
    interval: root.confirmWindowMs
    onTriggered: root.confirming = ""
  }

  onOpenedChanged: if (!opened) confirming = ""

  // ---------------------------------------------------------------- audio
  function nodeOptions(nodes) {
    var list = []
    for (var i = 0; i < (nodes || []).length; i++)
      list.push({ value: String(nodes[i].id), label: audio.nodeLabel(nodes[i]) })
    return list
  }

  function nodeById(nodes, id) {
    for (var i = 0; i < (nodes || []).length; i++)
      if (String(nodes[i].id) === id) return nodes[i]
    return null
  }

  property real wheelAccumulator: 0

  // ---------------------------------------------------------------- bar
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // macOS-style icon: two stacked switches, the top one on (solid capsule,
  // knob punched out on the right) and the bottom one off (outlined capsule,
  // solid knob on the left). Vector shapes so it stays crisp at fractional
  // scales; sized off the bar's icon font so its ink matches the neighboring
  // glyphs (13x11 at the default 13px).
  readonly property real iconUnit: Style.bar.iconFont
  readonly property real switchWidth: iconUnit * 1.0
  readonly property real switchHeight: iconUnit * 0.385
  readonly property real switchGap: iconUnit * 0.12
  readonly property real switchStroke: Math.max(1, iconUnit * 0.09)

  component SwitchGlyph: Shape {
    id: glyph
    property bool on: false
    property color color: "white"
    readonly property real r: height / 2
    // Knob: on = hole inset from the solid track; off = a solid dot the full
    // height of the track, capping its left end.
    readonly property real knobR: on ? r - root.switchStroke * 1.2 : r
    readonly property real knobX: on ? width - r : r
    // Strokes are centered on the path, so pull the outline in by half.
    readonly property real inset: on ? 0 : root.switchStroke / 2

    function capsule(i) {
      var w = width, h = height, rr = r - i
      return "M " + (i + rr) + " " + i
        + " L " + (w - i - rr) + " " + i
        + " A " + rr + " " + rr + " 0 0 1 " + (w - i - rr) + " " + (h - i)
        + " L " + (i + rr) + " " + (h - i)
        + " A " + rr + " " + rr + " 0 0 1 " + (i + rr) + " " + i + " Z"
    }
    function circle(cx, cy, cr) {
      return "M " + (cx - cr) + " " + cy
        + " A " + cr + " " + cr + " 0 1 0 " + (cx + cr) + " " + cy
        + " A " + cr + " " + cr + " 0 1 0 " + (cx - cr) + " " + cy + " Z"
    }

    width: root.switchWidth
    height: root.switchHeight
    preferredRendererType: Shape.CurveRenderer

    // Track: solid with the knob punched out when on, outlined when off.
    ShapePath {
      fillColor: glyph.on ? glyph.color : "transparent"
      fillRule: ShapePath.OddEvenFill
      strokeColor: glyph.on ? "transparent" : glyph.color
      strokeWidth: glyph.on ? -1 : root.switchStroke
      PathSvg {
        path: glyph.capsule(glyph.inset)
          + (glyph.on ? " " + glyph.circle(glyph.knobX, glyph.r, glyph.knobR) : "")
      }
    }

    // Solid knob when off.
    ShapePath {
      fillColor: glyph.on ? "transparent" : glyph.color
      strokeColor: "transparent"
      strokeWidth: -1
      PathSvg { path: glyph.on ? "" : glyph.circle(glyph.knobX, glyph.r, glyph.knobR) }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    // Non-empty so the button counts as having visual content; the icon is
    // drawn by the Column below.
    text: " "
    tooltipText: "Control Center"
    fixedWidth: root.switchWidth + Style.spaceReal(8.5) * 2

    onPressed: function(b) {
      if (b === Qt.RightButton) { if (root.audio) root.audio.toggleOutputMute() }
      else root.toggle()
    }

    onWheelMoved: function(delta) {
      if (!root.audio || !root.audio.hasOutput) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      var volume = root.audio.setOutputVolume(root.audio.outputVolume + wheel.steps * 0.05)
      root.audio.showVolumeOsd(volume)
    }

    Column {
      anchors.centerIn: parent
      spacing: root.switchGap

      SwitchGlyph { on: true; color: button.foreground }
      SwitchGlyph { on: false; color: button.foreground }
    }
  }

  // ---------------------------------------------------------------- popup
  component RowText: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
    Layout.fillWidth: true
  }

  // One audio direction: mute button on the icon, slider, percentage, and a
  // device picker underneath.
  component VolumeSection: ColumnLayout {
    id: section
    property string title: ""
    property string icon: ""
    property real volume: 0
    property bool muted: false
    property bool available: false
    property var devices: []
    property var current: null
    property var setVolume: null
    property var toggleMute: null
    property var setDevice: null

    Layout.fillWidth: true
    spacing: Style.space(6)

    PanelSectionHeader {
      text: section.title
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)

      PanelActionButton {
        iconText: section.icon
        tooltipText: section.muted ? "Unmute" : "Mute"
        foreground: section.muted ? root.dim : root.foreground
        fontFamily: root.fontFamily
        enabled: section.available
        onClicked: section.toggleMute()
      }

      PanelSlider {
        bar: root.bar
        Layout.fillWidth: true
        Layout.preferredHeight: Style.spacing.controlHeight
        minimum: 0
        maximum: 1
        step: 0.05
        value: section.volume
        opacity: section.muted ? 0.5 : 1.0
        enabled: section.available
        onMoved: function(v) { section.setVolume(v) }
        onRightClicked: section.toggleMute()
      }

      Text {
        textFormat: Text.PlainText
        text: Math.round(section.volume * 100) + "%"
        color: section.muted ? root.dim : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignRight
        Layout.preferredWidth: Style.space(34)
      }
    }

    Dropdown {
      Layout.fillWidth: true
      showLabel: false
      visible: section.devices.length > 0
      options: root.audio ? root.nodeOptions(section.devices) : []
      value: section.current ? String(section.current.id) : ""
      fontFamily: root.fontFamily
      onChanged: function(v) {
        var node = root.nodeById(section.devices, v)
        if (node) section.setDevice(node)
      }
    }
  }

  // Icon, name + status, optional switch, and a chevron into the full panel.
  component LinkRow: RowLayout {
    id: link
    property string icon: ""
    property string title: ""
    property string status: ""
    property bool showSwitch: false
    property bool switchOn: false
    property string switchTooltip: ""
    property var target: null
    signal switchToggled()

    Layout.fillWidth: true
    spacing: Style.space(10)

    Text {
      textFormat: Text.PlainText
      text: link.icon
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.icon
      horizontalAlignment: Text.AlignHCenter
      Layout.preferredWidth: Style.space(22)
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0
      RowText { text: link.title }
      RowText { text: link.status; color: root.dim; font.pixelSize: Style.font.bodySmall }
    }

    ToggleSwitch {
      visible: link.showSwitch
      checked: link.switchOn
      onToggled: link.switchToggled()
    }

    PanelActionButton {
      iconText: ""
      tooltipText: "Open " + link.title + " settings"
      foreground: root.foreground
      fontFamily: root.fontFamily
      enabled: link.target !== null
      onClicked: root.openPeer(link.target)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ColumnLayout {
        id: column
        width: parent.width
        spacing: Style.space(12)

        // Power / session actions, spread evenly across the panel width.
        PanelSectionHeader {
          text: "SESSION"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: 0

          Repeater {
            model: root.powerActions

            Item {
              id: powerCell
              required property var modelData
              Layout.fillWidth: true
              implicitHeight: powerButton.implicitHeight

              PanelActionButton {
                id: powerButton
                readonly property var modelData: powerCell.modelData
                readonly property bool armed: root.confirming === modelData.id
                anchors.centerIn: parent
                iconText: modelData.icon
                tooltipText: armed ? ("Click again to " + modelData.label.toLowerCase()) : modelData.label
                foreground: armed ? root.urgent : root.foreground
                hoverColor: modelData.confirm ? root.urgent : root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.iconLarge
                onClicked: root.triggerPower(modelData)
              }
            }
          }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

        VolumeSection {
          title: "OUTPUT"
          icon: root.outputIcon !== "" ? root.outputIcon : ""
          volume: root.audio ? root.audio.outputVolume : 0
          muted: root.audio ? root.audio.outputMuted : false
          available: !!(root.audio && root.audio.sink)
          devices: root.audio ? root.audio.candidateSinks : []
          current: root.audio ? root.audio.sink : null
          setVolume: function(v) { root.audio.setOutputVolume(v) }
          toggleMute: function() { root.audio.toggleOutputMute() }
          setDevice: function(node) { root.audio.setDefaultSink(node) }
        }

        VolumeSection {
          title: "INPUT"
          icon: root.inputIcon
          volume: root.audio ? root.audio.inputVolume : 0
          muted: root.audio ? root.audio.inputMuted : false
          available: !!(root.audio && root.audio.source)
          devices: root.audio ? root.audio.candidateSources : []
          current: root.audio ? root.audio.source : null
          setVolume: function(v) { root.audio.setInputVolume(v) }
          toggleMute: function() { root.audio.toggleInputMute() }
          setDevice: function(node) { root.audio.setDefaultSource(node) }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

        LinkRow {
          icon: root.networkIcon
          title: "Network"
          status: root.networkStatus
          showSwitch: !!(root.network && root.network.canToggleWifi)
          switchOn: Networking.wifiEnabled
          target: root.network
          onSwitchToggled: root.network.toggleNetwork()
        }

        LinkRow {
          icon: root.bluetoothIcon !== "" ? root.bluetoothIcon : "󰂲"
          title: "Bluetooth"
          status: root.bluetoothStatus
          showSwitch: !!(root.bluetooth && root.bluetooth.adapter)
          switchOn: root.bluetoothOn
          target: root.bluetooth
          onSwitchToggled: root.bluetooth.toggleBluetooth()
        }

        LinkRow {
          icon: "󰍹"
          title: "Displays"
          status: "Layout, scaling, profiles"
          target: root.display
        }
      }
    }
  }
}
