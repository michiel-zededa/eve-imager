/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 ZEDEDA, Inc.
 *
 * A square, borderless button that shows one ImIcon (top-bar actions).
 */

import QtQuick
import QtQuick.Controls

import RpiImager

AbstractButton {
    id: control

    property string iconName: ""
    /** Read by screen readers and shown as a tooltip; an icon alone says nothing. */
    property string label: ""

    implicitWidth: Style.scaled(36)
    implicitHeight: Style.scaled(36)
    activeFocusOnTab: true
    focusPolicy: Qt.TabFocus
    hoverEnabled: true

    background: Rectangle {
        radius: Style.controlBorderRadius
        color: (control.hovered || control.down) ? Style.surface2 : "transparent"
        border.color: control.activeFocus ? Style.focusOutlineColor : "transparent"
        border.width: control.activeFocus ? Style.focusOutlineWidth : 0
        antialiasing: true
    }

    contentItem: Item {
        ImIcon {
            anchors.centerIn: parent
            name: control.iconName
            size: Style.scaled(18)
            color: (control.hovered || control.down) ? Style.text : Style.muted
        }
    }

    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()

    ToolTip.visible: hovered && label.length > 0
    ToolTip.delay: 600
    ToolTip.text: label

    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.onPressAction: clicked()
}
