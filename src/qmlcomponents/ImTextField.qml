/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Raspberry Pi Ltd
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Templates as T
import RpiImager

pragma ComponentBehavior: Bound

// Built on the unstyled template, so the field looks the same on every
// platform: a bordered, rounded box whose border turns accent on focus.
T.TextField {
    id: root

    font.family: Style.fontFamily
    font.pointSize: Style.fontSizeInput

    implicitWidth: Style.scaled(200)
    implicitHeight: Style.scaled(40)
    leftPadding: Style.scaled(12)
    rightPadding: Style.scaled(12)
    topPadding: 0
    bottomPadding: 0
    verticalAlignment: TextInput.AlignVCenter

    color: enabled ? Style.text : Style.disabledText
    selectionColor: Style.accent
    selectedTextColor: Style.accentContrast
    placeholderTextColor: Style.disabledText

    background: Rectangle {
        color: root.enabled ? Style.surface : Style.surface2
        radius: Style.controlBorderRadius
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? Style.accent : Style.border
    }

    // Placeholder, shown while the field is empty
    Text {
        anchors.fill: parent
        anchors.leftMargin: root.leftPadding
        anchors.rightMargin: root.rightPadding
        verticalAlignment: Text.AlignVCenter
        text: root.placeholderText
        font: root.font
        color: root.placeholderTextColor
        elide: Text.ElideRight
        visible: root.length === 0 && root.preeditText.length === 0
        Accessible.ignored: true
    }

    // Sensible defaults to ensure consistent behavior across the app
    activeFocusOnPress: true
    activeFocusOnTab: true
    focusPolicy: Qt.TabFocus
    selectByMouse: true
    persistentSelection: true
    cursorVisible: activeFocus
    
    // Accessibility properties
    Accessible.role: Accessible.EditableText
    Accessible.name: placeholderText !== "" ? placeholderText : text
    Accessible.description: ""
    Accessible.editable: true
    Accessible.focused: activeFocus
    Accessible.passwordEdit: echoMode === TextInput.Password

    // Context menu for right-click with cut/copy/paste
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        cursorShape: Qt.IBeamCursor
        propagateComposedEvents: true
        
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                contextMenu.popup()
                mouse.accepted = true
            } else {
                mouse.accepted = false
            }
        }
        
        // Let other events pass through to TextField
        onPressed: function(mouse) {
            if (mouse.button !== Qt.RightButton) {
                mouse.accepted = false
            }
        }
        onReleased: function(mouse) {
            if (mouse.button !== Qt.RightButton) {
                mouse.accepted = false
            }
        }
        onDoubleClicked: function(mouse) {
            mouse.accepted = false
        }
        onPositionChanged: function(mouse) {
            mouse.accepted = false
        }
    }
    
    Menu {
        id: contextMenu

        // On Linux (X11/Wayland), QClipboard::dataChanged is not reliably
        // emitted for external clipboard changes, so force a fresh check
        // each time the context menu opens.
        onAboutToShow: ClipboardHelper.refresh()

        MenuItem {
            text: qsTr("Cut")
            enabled: root.selectedText.length > 0 && !root.readOnly && root.echoMode === TextInput.Normal
            Accessible.role: Accessible.MenuItem
            Accessible.name: text
            onTriggered: {
                // Copy to clipboard then remove selection
                ClipboardHelper.setText(root.selectedText)
                root.remove(root.selectionStart, root.selectionEnd)
            }
        }
        MenuItem {
            text: qsTr("Copy")
            enabled: root.selectedText.length > 0 && root.echoMode === TextInput.Normal
            Accessible.role: Accessible.MenuItem
            Accessible.name: text
            onTriggered: {
                ClipboardHelper.setText(root.selectedText)
            }
        }
        MenuItem {
            text: qsTr("Paste")
            enabled: !root.readOnly && ClipboardHelper.hasText
            Accessible.role: Accessible.MenuItem
            Accessible.name: text
            onTriggered: {
                var clipText = ClipboardHelper.getText()
                if (clipText.length > 0) {
                    root.insert(root.cursorPosition, clipText)
                }
            }
        }
        MenuSeparator {}
        MenuItem {
            text: qsTr("Select All")
            enabled: root.text.length > 0
            Accessible.role: Accessible.MenuItem
            Accessible.name: text
            onTriggered: root.selectAll()
        }
    }

    // No special key handling here; rely on WizardStepBase auto wiring
}




