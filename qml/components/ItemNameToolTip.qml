import QtQuick
import QtQuick.Controls

ToolTip {
    id: itemNameToolTip
    required property Item pageHost

    property MouseArea mouseArea: null
    property bool hoverAllowed: true

    parent:  Overlay.overlay

    // 将鼠标在 MouseArea 中的局部坐标转换为 Tooltip 父对象坐标
    property point cursorPos: mouseArea
                               ? mouseArea.mapToItem(
                                     itemNameToolTip.parent,
                                     mouseArea.mouseX,
                                     mouseArea.mouseY
                                 )
                               : Qt.point(0, 0)

    // 跟随鼠标，向右下偏移
    x: cursorPos.x + 14
    y: cursorPos.y + 20

    delay: 800
    timeout: -1

    visible: mouseArea !== null
             && mouseArea.containsMouse
             && !mouseArea.pressed
             && hoverAllowed

    modal: false
    dim: false
    focus: false
    closePolicy: Popup.NoAutoClose

    padding: 10
    topPadding: 7
    bottomPadding: 7

    contentItem: Text {
        id: itemNameToolTipText

        text: itemNameToolTip.text

        width: Math.max(
                   1,
                   Math.min(360, Math.ceil(itemNameToolTipMetrics.advanceWidth))
               )

        color: pageHost.textDarkColor
        font.pixelSize: 11
        font.weight: Font.Medium
        wrapMode: Text.WrapAnywhere
    }

    background: Rectangle {
        color: pageHost.panelColor
        border.color: "#DCE4F4"
        border.width: 1
        radius: 7
    }

    TextMetrics {
        id: itemNameToolTipMetrics
        font: itemNameToolTipText.font
        text: itemNameToolTipText.text
    }
}
