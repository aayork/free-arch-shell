import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "../../notifications/NotificationLogic.js" as NotificationLogic

// One compact line-pair in the clock popup's notification list: small icon,
// "App · 5m ago", summary and a one-line body. Repeats of the same message
// arrive stacked, with `count` shown as a badge. Click to act on it, hover
// for the dismiss button.
CursorSurface {
  id: row

  property var entry: null
  property int count: 1
  property string caption: ""
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family

  signal activated()
  signal dismissed()

  readonly property string bodyText: entry ? NotificationLogic.sanitizeBody(entry.body, entry.app, entry.appIcon).replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim() : ""

  function iconUrl(value) {
    var v = String(value || "")
    if (v === "") return ""
    if (v.indexOf("file://") === 0) return v
    if (v.indexOf("image://") === 0) return ""
    if (v.charAt(0) === "/") return Util.fileUrl(v)
    return Quickshell.hasThemeIcon(v) ? Quickshell.iconPath(v) : ""
  }

  readonly property string iconSource: entry ? (iconUrl(entry.image) || iconUrl(entry.appIcon)) : ""

  hasCursor: hover.hovered
  implicitHeight: content.implicitHeight + Style.space(12)

  HoverHandler { id: hover }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) row.dismissed()
      else row.activated()
    }
  }

  RowLayout {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    spacing: Style.space(10)

    Item {
      Layout.preferredWidth: Style.space(22)
      Layout.preferredHeight: Style.space(22)
      Layout.alignment: Qt.AlignTop

      Image {
        id: icon
        anchors.fill: parent
        visible: status === Image.Ready
        source: row.iconSource
        sourceSize.width: width * Screen.devicePixelRatio
        sourceSize.height: height * Screen.devicePixelRatio
        fillMode: Image.PreserveAspectFit
        asynchronous: true
      }

      Text {
        anchors.centerIn: parent
        visible: !icon.visible
        textFormat: Text.PlainText
        text: row.entry && row.entry.glyph ? row.entry.glyph : "󰂚"
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.heading
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(1)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: row.caption
          color: row.dim
          font.family: row.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          visible: row.count > 1 && !hover.hovered
          text: "×" + row.count
          color: row.dim
          font.family: row.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          textFormat: Text.PlainText
          visible: hover.hovered
          text: "✕"
          color: dismissArea.containsMouse ? row.foreground : row.dim
          font.pixelSize: Style.font.caption

          MouseArea {
            id: dismissArea
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.dismissed()
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        visible: text !== ""
        text: row.entry ? row.entry.summary : ""
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        visible: text !== ""
        text: row.bodyText
        color: row.dim
        font.family: row.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }
  }
}
