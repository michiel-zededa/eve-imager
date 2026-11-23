/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 ZEDEDA, Inc.
 *
 * An on/off switch: a pill-shaped track with a round knob, accent when on.
 * It has no label of its own; set accessibleName to what it switches.
 */

import QtQuick
import QtQuick.Templates as T

import RpiImager

T.Switch {
    id: control

    property string accessibleName: ""

    implicitWidth: Style.scaled(40)
    implicitHeight: Style.scaled(22)
    activeFocusOnTab: true
    focusPolicy: Qt.TabFocus
    hoverEnabled: true

    indicator: Rectangle {
        width: control.width
        height: control.height
        radius: height / 2
        color: !control.enabled ? Style.surface2
             : control.checked ? Style.formControlActiveColor : Style.formControlBorderColor
        border.width: control.activeFocus ? 2 : 0
        border.color: Style.accentStrong
        Behavior on color { ColorAnimation { duration: 120 } }

        Rectangle {
            width: parent.height - 6
            height: width
            radius: width / 2
            y: 3
            x: control.checked ? parent.width - width - 3 : 3
            color: "#ffffff"
            Behavior on x { NumberAnimation { duration: 120 } }
        }
    }

    Accessible.role: Accessible.CheckBox
    Accessible.name: control.accessibleName
    Accessible.checkable: true
    Accessible.checked: control.checked
    Accessible.onToggleAction: control.toggle()
    Accessible.onPressAction: control.toggle()

    Keys.onReturnPressed: control.toggle()
    Keys.onEnterPressed: control.toggle()
}
