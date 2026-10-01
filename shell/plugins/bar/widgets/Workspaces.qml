import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "roseshell.workspaces"

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceIds() {
    // Two are always there, the way GNOME starts out. Anything past that shows
    // only while Hyprland has it, and Hyprland drops an empty workspace the
    // moment it is left, so a third appears when entered and goes when vacated.
    var ids = [1, 2]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)
  readonly property real dotSize: Math.round(Style.spaceReal(7))
  readonly property real pillLength: Math.round(Style.spaceReal(22))
  readonly property real dotGap: Math.round(Style.spaceReal(8))

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: 0
    rowSpacing: 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        id: slot
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
        // Pill-expand style: every workspace is a small dot and the focused
        // one stretches into a pill along the bar's axis.
        readonly property real pillLength: focused ? root.pillLength : root.dotSize

        bar: root.bar
        labelVisible: false
        hasVisualContent: true
        tooltipText: modelData === 10 ? "Workspace 0" : "Workspace " + modelData
        // Same colour rules as the old numbered style: accent for focused,
        // dimmed accent for occupied, faint foreground for empty. On a
        // transparent bar everything follows barForeground and opacity alone
        // separates the states.
        foreground: (root.bar && root.bar.transparent)
          ? root.bar.barForeground
          : (focused ? Color.accent : (occupied ? Util.alpha(Color.accent, 0.8) : (root.bar ? root.bar.barForeground : Color.foreground)))
        fixedWidth: root.vertical ? root.barSize : slot.pillLength + root.dotGap
        fixedHeight: root.vertical ? slot.pillLength + root.dotGap : root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }

        Behavior on fixedWidth {
          enabled: !root.vertical
          NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on fixedHeight {
          enabled: root.vertical
          NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        Rectangle {
          anchors.centerIn: parent
          width: root.vertical ? root.dotSize : slot.pillLength
          height: root.vertical ? slot.pillLength : root.dotSize
          radius: root.dotSize / 2
          color: slot.foreground
          opacity: slot.focused || slot.occupied ? 1 : 0.35

          Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
          Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
          Behavior on color { ColorAnimation { duration: 160 } }
          Behavior on opacity { NumberAnimation { duration: 160 } }
        }
      }
    }
  }
}
