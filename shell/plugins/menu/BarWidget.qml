import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "roseshell.menu"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\ue900"
    fontFamily: "roseshell"
    horizontalMargin: 7.5
    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("roseshell-shell shell toggle roseshell.menu '{\"menu\":\"root\"}'")
    }
  }
}
