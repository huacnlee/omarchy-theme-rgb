pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui

// The panel's "more" menu: a small icon button that drops a list of the
// actions which do not earn a control of their own. The popup is drawn the
// way the kit's Dropdown draws its list (popup surface colours, foreground-
// tinted cursor row, square corners), so it reads as part of the panel.
//
// `entries` is [{ id, label, enabled }] plus `{ separator: true }` markers;
// activating a row emits `activated(id)` and closes the menu. The owning
// panel binds `panelOpen` so the popup goes away with the panel, and reads
// `opened` to suspend its own key handling while the list has the keys.
Item {
  id: menu

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property var entries: []
  property string tooltipText: "More"
  property bool panelOpen: true
  readonly property bool opened: popup.opened
  readonly property var popupBorderSpec: Border.localOrSurfaceSpec(
    "popups", "border", Color.popups.border, Color.popups.border, Style.normalBorderWidth)

  signal activated(string id)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function open() { popup.open() }
  function close() { popup.close() }
  function toggle() { popup.opened ? popup.close() : popup.open() }

  function isRow(index) {
    var e = entries[index]
    return !!e && !e.separator && e.enabled !== false
  }

  // The keyboard cursor only ever rests on a row it can activate.
  function nextRow(from, direction) {
    for (var i = from + direction; i >= 0 && i < entries.length; i += direction)
      if (isRow(i)) return i
    return from
  }

  function activate(index) {
    if (!isRow(index)) return
    var id = String(entries[index].id)
    popup.close()
    menu.activated(id)
  }

  onPanelOpenChanged: if (!panelOpen) popup.close()

  PanelActionButton {
    id: button
    anchors.fill: parent
    iconText: "󰇘"
    tooltipText: popup.opened ? "" : menu.tooltipText
    foreground: menu.foreground
    fontFamily: menu.fontFamily
    hasCursor: popup.opened
    onClicked: menu.toggle()
  }

  QQC.Popup {
    id: popup
    x: button.width - width
    y: button.height + Style.spacing.xxs
    width: Style.space(176)
    implicitHeight: rows.contentHeight + topPadding + bottomPadding
    leftPadding: Border.left(menu.popupBorderSpec) + Style.spacing.hairline
    rightPadding: Border.right(menu.popupBorderSpec) + Style.spacing.hairline
    topPadding: Border.top(menu.popupBorderSpec) + Style.spacing.hairline
    bottomPadding: Border.bottom(menu.popupBorderSpec) + Style.spacing.hairline
    modal: false
    focus: true
    closePolicy: QQC.Popup.CloseOnEscape | QQC.Popup.CloseOnPressOutside

    background: BorderSurface {
      color: Color.popups.background
      borderSpec: menu.popupBorderSpec
      radius: Style.cornerRadius
    }

    onOpened: {
      rows.currentIndex = menu.nextRow(-1, 1)
      rows.forceActiveFocus()
    }

    contentItem: ListView {
      id: rows
      implicitHeight: contentHeight
      clip: true
      interactive: false
      boundsBehavior: Flickable.StopAtBounds
      model: menu.entries
      currentIndex: -1

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { popup.close(); event.accepted = true }
        else if (event.key === Qt.Key_Down || event.text === "j") {
          rows.currentIndex = menu.nextRow(rows.currentIndex, 1); event.accepted = true
        } else if (event.key === Qt.Key_Up || event.text === "k") {
          rows.currentIndex = menu.nextRow(rows.currentIndex, -1); event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
          menu.activate(rows.currentIndex); event.accepted = true
        }
      }

      delegate: Item {
        id: row
        required property var modelData
        required property int index

        readonly property bool separator: !!modelData.separator
        readonly property bool hot: rows.currentIndex === index
        readonly property bool rowEnabled: !separator && modelData.enabled !== false

        width: rows.width
        height: separator ? Style.spacing.md * 2 + 1 : Style.spacing.popupRowHeight

        PanelSeparator {
          visible: row.separator
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          foreground: menu.foreground
        }

        Rectangle {
          anchors.fill: parent
          visible: !row.separator
          color: row.hot && row.rowEnabled ? Style.hoverFillFor(menu.foreground, Color.accent) : "transparent"
          radius: Style.cornerRadius

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.controlPaddingX
            anchors.rightMargin: Style.spacing.controlPaddingX
            text: row.separator ? "" : String(row.modelData.label)
            color: !row.rowEnabled
              ? Qt.darker(menu.foreground, 2.0)
              : (row.hot ? Style.hoverStateColor(menu.foreground, Color.accent) : menu.foreground)
            font.family: menu.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            enabled: row.rowEnabled
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: rows.currentIndex = row.index
            onClicked: menu.activate(row.index)
          }
        }
      }
    }
  }
}
