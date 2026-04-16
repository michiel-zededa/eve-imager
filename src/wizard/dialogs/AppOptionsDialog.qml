/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Raspberry Pi Ltd
 */

import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../qmlcomponents"

import RpiImager

BaseDialog {
    id: popup
    
    // Override default height for this more complex dialog
    height: Math.max(280, contentLayout ? (contentLayout.implicitHeight + Style.cardPadding * 2) : 280)
    
    // imageWriter is inherited from BaseDialog
    // Optional reference to the wizard container for ephemeral flags
    property var wizardContainer: null
    
    property bool initialized: false
    property bool isInitializing: false

    // Custom escape handling
    function escapePressed() {
        popup.close()
    }

    // Dynamic width that updates when language/text changes
    implicitWidth: Math.max(
        chkBeep.naturalWidth,
        chkEject.naturalWidth,
        chkTelemetry.naturalWidth,
        chkDisableWarnings.naturalWidth
    ) + Style.cardPadding * 4  // Double padding: contentLayout + optionsLayout margins

    // Register focus groups when component is ready
    Component.onCompleted: {
        // Register focus groups
        registerFocusGroup("header", function(){
            // Only include header text when screen reader is active (otherwise it's not focusable)
            if (popup.imageWriter && popup.imageWriter.isScreenReaderActive()) {
                return [headerText]
            }
            return []
        }, 0)
        registerFocusGroup("options", function(){
            var items = [chkBeep.focusItem, chkEject.focusItem, chkTelemetry.focusItem]
            // Include telemetry help link if visible
            if (chkTelemetry.helpLinkItem && chkTelemetry.helpLinkItem.visible)
                items.push(chkTelemetry.helpLinkItem)
            items.push(chkDisableWarnings.focusItem)
            return items
        }, 1)
        registerFocusGroup("buttons", function(){
            return [cancelButton, saveButton]
        }, 2)
    }

    // Header
    Text {
        id: headerText
        text: qsTr("App Options")
        font.pointSize: Style.fontSizeLargeHeading
        font.family: Style.fontFamilyBold
        font.bold: true
        color: Style.formLabelColor
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        Accessible.role: Accessible.Heading
        Accessible.name: text
        Accessible.focusable: popup.imageWriter ? popup.imageWriter.isScreenReaderActive() : false
        focusPolicy: (popup.imageWriter && popup.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
        activeFocusOnTab: popup.imageWriter ? popup.imageWriter.isScreenReaderActive() : false
    }

    // Options section
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: optionsLayout.implicitHeight + Style.cardPadding

        ColumnLayout {
            id: optionsLayout
            anchors.fill: parent
            anchors.margins: Style.cardPadding
            spacing: Style.spacingMedium

            ImOptionPill {
                id: chkBeep
                text: qsTr("Play sound when finished")
                accessibleDescription: imageWriter.isBeepAvailable() 
                    ? qsTr("Play an audio notification when the image write process completes")
                    : qsTr("Audio notification unavailable - no viable audio player found on this system")
                Layout.fillWidth: true
                enabled: imageWriter.isBeepAvailable()
                Component.onCompleted: {
                    focusItem.activeFocusOnTab = true
                }
            }

            ImOptionPill {
                id: chkEject
                text: qsTr("Eject media when finished")
                accessibleDescription: qsTr("Automatically eject the storage device when the write process completes successfully")
                Layout.fillWidth: true
                Component.onCompleted: {
                    focusItem.activeFocusOnTab = true
                }
            }

            ImOptionPill {
                id: chkTelemetry
                text: qsTr("Enable anonymous statistics (telemetry)")
                accessibleDescription: qsTr("Send anonymous usage statistics to help improve EVE OS Imager")
                helpLabel: imageWriter.isEmbeddedMode() ? "" : qsTr("What is this?")
                helpUrl: imageWriter.isEmbeddedMode() ? "" : "https://github.com/lf-edge/eve"
                Layout.fillWidth: true
                Component.onCompleted: {
                    focusItem.activeFocusOnTab = true
                }
            }

            ImOptionPill {
                id: chkDisableWarnings
                text: qsTr("Disable warnings")
                accessibleDescription: qsTr("Skip confirmation dialogs before writing images (advanced users only)")
                Layout.fillWidth: true
                Component.onCompleted: {
                    focusItem.activeFocusOnTab = true
                }
                onCheckedChanged: {
                    // Don't trigger confirmation dialog during initialization
                    if (popup.isInitializing) {
                        return;
                    }
                    
                    if (checked) {
                        // Confirm before enabling this risky setting
                        confirmDisableWarnings.open();
                    } else if (popup.wizardContainer) {
                        popup.wizardContainer.disableWarnings = false;
                    }
                }
            }

        }
    }

    // Spacer
    Item {
        Layout.fillHeight: true
    }

    // Version display - only shown when window has no decorations (no title bar)
    Text {
        id: versionText
        text: qsTr("Version: %1").arg(imageWriter.constantVersion())
        font.pointSize: Style.fontSizeCaption
        font.family: Style.fontFamily
        color: Style.textDescriptionColor
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        visible: !imageWriter.hasWindowDecorations()
        Layout.bottomMargin: Style.spacingSmall
    }

    // Buttons section with background
    Rectangle {
        Layout.fillWidth: true
        // Ensure minimum width accommodates buttons
        Layout.minimumWidth: cancelButton.implicitWidth + saveButton.implicitWidth + Style.spacingMedium * 2 + Style.cardPadding
        Layout.preferredHeight: buttonRow.implicitHeight + Style.cardPadding
        color: Style.titleBackgroundColor

        RowLayout {
            id: buttonRow
            anchors.fill: parent
            anchors.margins: Style.cardPadding / 2
            spacing: Style.spacingMedium

            Item {
                Layout.fillWidth: true
            }

            ImButton {
                id: cancelButton
                text: CommonStrings.cancel
                accessibleDescription: qsTr("Close the options dialog without saving any changes")
                Layout.minimumWidth: Style.buttonWidthMinimum
                activeFocusOnTab: true
                onClicked: {
                    popup.close();
                }
            }

            ImButtonRed {
                id: saveButton
                text: qsTr("Save")
                accessibleDescription: qsTr("Save the selected options and apply them to EVE OS Imager")
                Layout.minimumWidth: Style.buttonWidthMinimum
                activeFocusOnTab: true
                onClicked: {
                    popup.applySettings();
                    popup.close();
                }
            }
        }
    }

    function initialize() {
        var firstOpen = !initialized;

        // Set flag to prevent onCheckedChanged handlers from triggering dialogs
        isInitializing = true;

        // (Re)load current settings from ImageWriter so that Cancel discards changes
        // Only enable beep if it's both saved as enabled AND available on this system
        chkBeep.checked = imageWriter.getBoolSetting("beep") && imageWriter.isBeepAvailable();
        chkEject.checked = imageWriter.getBoolSetting("eject");
        chkTelemetry.checked = imageWriter.getBoolSetting("telemetry");
        // Do not load from QSettings; keep ephemeral
        chkDisableWarnings.checked = popup.wizardContainer ? popup.wizardContainer.disableWarnings : false;

        initialized = true;
        // Clear initialization flag
        isInitializing = false;

        // Pre-compute final height before opening to avoid first-show reflow
        if (firstOpen) {
            var desired = contentLayout ? (contentLayout.implicitHeight + Style.cardPadding * 2) : 280;
            popup.height = Math.max(280, desired);
        }
    }

    function applySettings() {
        // Save settings to ImageWriter
        // Only save beep as enabled if it's actually available on this system
        imageWriter.setSetting("beep", chkBeep.checked && imageWriter.isBeepAvailable());
        imageWriter.setSetting("eject", chkEject.checked);
        imageWriter.setSetting("telemetry", chkTelemetry.checked);
        // Do not persist disable_warnings; set ephemeral flag only
        if (popup.wizardContainer)
            popup.wizardContainer.disableWarnings = chkDisableWarnings.checked;
    }

    onOpened: {
        initialize();
        // BaseDialog handles the focus management automatically
    }

    // Confirmation dialog for disabling warnings
    BaseDialog {
        id: confirmDisableWarnings
        imageWriter: popup.imageWriter
        parent: popup.contentItem
        anchors.centerIn: parent

        onClosed: {
            // If dialog was closed without confirming, revert the toggle
            if (!confirmAccepted) {
                chkDisableWarnings.checked = false;
            }
            confirmAccepted = false;
        }

        property bool confirmAccepted: false

        // Custom escape handling
        function escapePressed() {
            confirmDisableWarnings.close()
        }

        // Register focus groups when component is ready
        Component.onCompleted: {
            registerFocusGroup("content", function(){ 
                // Only include text elements when screen reader is active (otherwise they're not focusable)
                if (popup.imageWriter && popup.imageWriter.isScreenReaderActive()) {
                    return [confirmTitleText, confirmDescriptionText]
                }
                return []
            }, 0)
            registerFocusGroup("buttons", function(){ 
                return [confirmCancelButton, confirmDisableButton] 
            }, 1)
        }

        // Dialog content
        Text {
            id: confirmTitleText
            text: qsTr("Disable warnings?")
            font.pointSize: Style.fontSizeHeading
            font.family: Style.fontFamilyBold
            font.bold: true
            color: Style.formLabelColor
            Layout.fillWidth: true
            Accessible.role: Accessible.Heading
            Accessible.name: text
            Accessible.focusable: popup.imageWriter ? popup.imageWriter.isScreenReaderActive() : false
            focusPolicy: (popup.imageWriter && popup.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
            activeFocusOnTab: popup.imageWriter ? popup.imageWriter.isScreenReaderActive() : false
        }

        Text {
            id: confirmDescriptionText
            textFormat: Text.StyledText
            wrapMode: Text.WordWrap
            font.pointSize: Style.fontSizeDescription
            font.family: Style.fontFamily
            color: Style.textDescriptionColor
            Layout.fillWidth: true
            text: qsTr("If you disable warnings, EVE OS Imager will <b>not show confirmation prompts before writing images</b>. You will still be required to <b>type the exact name</b> when selecting a system drive.")
            Accessible.role: Accessible.StaticText
            Accessible.name: text.replace(/<[^>]+>/g, '')  // Strip HTML tags for accessibility
            Accessible.focusable: popup.imageWriter ? popup.imageWriter.isScreenReaderActive() : false
            focusPolicy: (popup.imageWriter && popup.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
            activeFocusOnTab: popup.imageWriter ? popup.imageWriter.isScreenReaderActive() : false
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacingMedium
            Item {
                Layout.fillWidth: true
            }

            ImButton {
                id: confirmCancelButton
                text: CommonStrings.cancel
                accessibleDescription: qsTr("Keep warnings enabled and return to the options dialog")
                activeFocusOnTab: true
                onClicked: confirmDisableWarnings.close()
            }

            ImButtonRed {
                id: confirmDisableButton
                text: qsTr("Disable warnings")
                accessibleDescription: qsTr("Disable confirmation prompts before writing images, requiring only exact name entry for system drives")
                activeFocusOnTab: true
                onClicked: {
                    confirmDisableWarnings.confirmAccepted = true;
                    if (popup.wizardContainer)
                        popup.wizardContainer.disableWarnings = true;
                    confirmDisableWarnings.close();
                }
            }
        }
    }

}

