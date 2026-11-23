/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 ZEDEDA, Inc.
 *
 * A text field that also offers a short list of known values: type anything,
 * or open the list and pick one.
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import RpiImager

Item {
    id: root

    property alias text: field.text
    property alias placeholderText: field.placeholderText
    property alias field: field
    property var suggestions: []
    property string accessibleName: ""

    implicitHeight: field.implicitHeight
    implicitWidth: Style.scaled(240)

    ImTextField {
        id: field
        anchors.fill: parent
        rightPadding: Style.scaled(40)
        inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhUrlCharactersOnly
        Accessible.name: root.accessibleName
        Keys.onDownPressed: popup.open()
    }

    ImIconButton {
        id: openButton
        anchors.right: parent.right
        anchors.rightMargin: Style.scaled(4)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.scaled(32)
        height: Style.scaled(32)
        iconName: "chevron-down"
        label: qsTr("Show known values")
        onClicked: popup.visible ? popup.close() : popup.open()
    }

    Popup {
        id: popup
        y: root.height + 4
        width: root.width
        padding: 4
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        background: Rectangle {
            color: Style.surface
            radius: Style.controlBorderRadius
            border.color: Style.border
            border.width: 1
        }

        contentItem: Column {
            spacing: 0
            Repeater {
                model: root.suggestions
                ItemDelegate {
                    id: option
                    required property string modelData
                    width: popup.availableWidth
                    height: Style.scaled(36)
                    padding: 0
                    highlighted: root.text === modelData

                    contentItem: Text {
                        text: option.modelData
                        leftPadding: Style.scaled(10)
                        font.family: Style.fontFamily
                        font.pointSize: Style.fontSizeInput
                        color: option.highlighted ? Style.accentText : Style.text
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    background: Rectangle {
                        radius: Style.controlBorderRadius - 2
                        color: option.highlighted ? Style.accentSoft
                             : option.hovered ? Style.surface2 : "transparent"
                    }
                    onClicked: {
                        root.text = modelData
                        popup.close()
                        field.forceActiveFocus()
                    }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData
                }
            }
        }
    }
}
