/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 ZEDEDA, Inc.
 *
 * A tab in the ZEDEDA product style: plain text, with an accent underline on
 * the selected tab. Use inside a TabBar whose background is ImTabBarLine or
 * transparent.
 */

import QtQuick
import QtQuick.Controls

import RpiImager

TabButton {
    id: control

    font.family: Style.fontFamily
    font.pointSize: Style.fontSizeFormLabel
    font.weight: Style.fontWeightMedium
    width: implicitWidth
    implicitHeight: Style.scaled(40)
    leftPadding: Style.spacingMedium
    rightPadding: Style.spacingMedium

    contentItem: Text {
        text: control.text
        font: control.font
        color: control.checked ? Style.text : (control.hovered ? Style.text : Style.muted)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Item {
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 3
            color: control.checked ? Style.accent : "transparent"
        }
        Rectangle {
            // keyboard focus ring
            anchors.fill: parent
            anchors.bottomMargin: 4
            radius: Style.controlBorderRadius
            color: "transparent"
            border.color: control.visualFocus ? Style.focusOutlineColor : "transparent"
            border.width: control.visualFocus ? Style.focusOutlineWidth : 0
        }
    }

    Accessible.role: Accessible.PageTab
    Accessible.name: text
}
