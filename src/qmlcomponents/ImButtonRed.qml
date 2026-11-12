/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2022 Raspberry Pi Ltd
 */

import QtQuick
import QtQuick.Controls

import RpiImager

Button {
    id: control
    font.family: Style.fontFamily
    font.pointSize: Style.fontSizeSm
    font.weight: Style.fontWeightMedium
    
    // Allow instances to provide a custom accessibility description
    property string accessibleDescription: ""

    // "danger" turns the filled button into an outlined red one, for actions
    // that stop or undo something (e.g. Cancel write)
    property bool danger: false
    
    // Access imageWriter from parent context
    property var imageWriter: {
        var item = parent;
        while (item) {
            if (item.imageWriter !== undefined) {
                return item.imageWriter;
            }
            item = item.parent;
        }
        return null;
    }

    background: Rectangle {
        color: !control.enabled ? Style.surface2
               : control.danger ? ((control.hovered || control.down) ? Style.errBg : Style.surface)
               : (control.hovered || control.down) ? Style.button2HoveredBackgroundColor : Style.button2BackgroundColor
        radius: (control.imageWriter && control.imageWriter.isEmbeddedMode()) ? Style.buttonBorderRadiusEmbedded : Style.controlBorderRadius
        // Keyboard focus: a ring in the page colour inside an accent outline
        border.color: control.danger && control.enabled ? (control.activeFocus ? Style.err : Style.errBorder)
                    : control.activeFocus ? Style.accentStrong : "transparent"
        border.width: control.activeFocus ? Style.focusOutlineWidth : (control.danger && control.enabled ? 1 : 0)
        antialiasing: true  // Smooth edges at non-integer scale factors
        clip: true  // Prevent content overflow at non-integer scale factors
    }

    // Size to fit content, with minimum width for short labels
    implicitWidth: Math.max(Style.buttonWidthMinimum, implicitContentWidth + leftPadding + rightPadding)

    contentItem: Text {
        text: control.text
        font: control.font
        color: !control.enabled ? Style.disabledText
             : control.danger ? Style.err : Style.button2ForegroundColor
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight  // Truncate if layout constrains button below content width
    }

    activeFocusOnTab: true
    focusPolicy: Qt.TabFocus
    
    // Accessibility properties
    Accessible.role: Accessible.Button
    Accessible.name: {
        // Combine text with description in name since VoiceOver reads name more reliably
        var name = text
        var desc = accessibleDescription
        if (!enabled && desc !== "") {
            return name + ", " + desc + " (disabled)"
        } else if (!enabled) {
            return name + " (disabled)"
        } else if (desc !== "") {
            return name + ", " + desc
        } else {
            return name
        }
    }
    Accessible.description: ""
    Accessible.onPressAction: clicked()
    
    Keys.onEnterPressed: clicked()
    Keys.onReturnPressed: clicked()
}
