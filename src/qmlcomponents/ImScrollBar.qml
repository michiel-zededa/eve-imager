/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 ZEDEDA, Inc.
 *
 * A thin, rounded scroll bar that is only there when the content overflows.
 */

import QtQuick
import QtQuick.Templates as T

import RpiImager

T.ScrollBar {
    id: control

    implicitWidth: Style.scrollBarWidth
    implicitHeight: Style.scrollBarWidth
    padding: 2
    minimumSize: 0.08
    visible: control.policy !== T.ScrollBar.AlwaysOff && control.size < 1.0

    contentItem: Rectangle {
        implicitWidth: Style.scrollBarWidth - 4
        implicitHeight: Style.scrollBarWidth - 4
        radius: width / 2
        color: control.pressed ? Style.muted
             : control.hovered ? Style.disabledText
             : Style.formControlBorderColor
    }

    background: Item {}
}
