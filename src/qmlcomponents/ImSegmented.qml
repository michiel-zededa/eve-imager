/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 ZEDEDA, Inc.
 *
 * A small either/or control: a grey track with one raised segment for the
 * current choice.
 *
 *   options: [ { value: "simple", label: "Simple" }, ... ]
 */

import QtQuick
import QtQuick.Templates as T

import RpiImager

Rectangle {
    id: root

    property var options: []
    property string value: ""
    property string accessibleName: ""
    signal selected(string value)

    implicitWidth: row.implicitWidth + 6
    implicitHeight: Style.scaled(36)
    radius: Style.controlBorderRadius
    color: Style.track

    Accessible.role: Accessible.Grouping
    Accessible.name: root.accessibleName

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: root.options

            T.AbstractButton {
                id: segment
                required property var modelData
                readonly property bool current: root.value === modelData.value

                implicitWidth: label.implicitWidth + Style.scaled(28)
                implicitHeight: root.implicitHeight - 6
                activeFocusOnTab: true
                focusPolicy: Qt.TabFocus
                hoverEnabled: true
                onClicked: root.selected(modelData.value)
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()

                background: Rectangle {
                    radius: Style.controlBorderRadius - 2
                    color: segment.current ? Style.surface
                         : segment.hovered ? Style.surface2 : "transparent"
                    border.width: segment.activeFocus ? 2 : (segment.current ? 1 : 0)
                    border.color: segment.activeFocus ? Style.accent : Style.border
                }
                contentItem: Text {
                    id: label
                    text: segment.modelData.label
                    font.family: Style.fontFamily
                    font.pointSize: Style.fontSizeDescription
                    font.weight: Style.fontWeightMedium
                    color: segment.current ? Style.text : Style.muted
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Accessible.role: Accessible.RadioButton
                Accessible.name: modelData.label
                Accessible.checkable: true
                Accessible.checked: current
                Accessible.onPressAction: clicked()
            }
        }
    }
}
