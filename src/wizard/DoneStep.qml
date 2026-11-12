/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2020 Raspberry Pi Ltd
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../qmlcomponents"

import RpiImager

WizardStepBase {
    id: root
    
    required property ImageWriter imageWriter
    required property var wizardContainer
    
    title: qsTr("Write complete")
    showBackButton: false
    showNextButton: false
    readonly property bool autoEjectEnabled: imageWriter.getBoolSetting("eject")

    component SummaryLabel: Text {
        font.pointSize: Style.fontSizeFormLabel
        font.family: Style.fontFamily
        color: Style.muted
        Layout.alignment: Qt.AlignTop
        Accessible.role: Accessible.StaticText
        Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
        focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
        activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
    }

    component SummaryValue: Text {
        font.pointSize: Style.fontSizeFormLabel
        font.family: Style.fontFamily
        color: Style.text
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
        Accessible.ignored: true   // Read as part of the label
    }

    // Content
    content: [
    ColumnLayout {
        anchors.fill: parent
        spacing: Style.spacingSmallPlus

        // Result: what to do with the drive now
        Rectangle {
            Layout.fillWidth: true
            color: Style.okBg
            border.color: Style.okBorder
            border.width: 1
            radius: Style.sectionBorderRadius
            implicitHeight: resultRow.implicitHeight + Style.cardPadding * 2

            RowLayout {
                id: resultRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.cardPadding
                spacing: Style.spacingSmallPlus

                ImIcon {
                    name: "check-circle"
                    color: Style.ok
                    size: Style.scaled(28)
                    Layout.alignment: Qt.AlignTop
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.spacingXXSmall

                    Text {
                        id: choicesHeading
                        text: qsTr("The installer drive is ready")
                        font.pointSize: Style.fontSizeHeading
                        font.family: Style.fontFamily
                        font.weight: Style.fontWeightSemiBold
                        color: Style.ok
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                        Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                        focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
                        activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                    }

                    Text {
                        id: ejectInstruction
                        text: root.autoEjectEnabled ? qsTr("The storage device was ejected automatically. You can now remove it safely.") : qsTr("Please eject the storage device before removing it from your computer.")
                        font.pointSize: Style.fontSizeDescription
                        font.family: Style.fontFamily
                        color: Style.text
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                        Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                        focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
                        activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                    }
                }
            }
        }

        // What was written
        ImCard {
            Layout.fillWidth: true
            padding: 0
            spacing: 0

            Text {
                text: qsTr("Written")
                font.family: Style.fontFamily
                font.pointSize: Style.fontSizeCaption
                font.weight: Style.fontWeightSemiBold
                font.letterSpacing: 1.1
                font.capitalization: Font.AllUppercase
                color: Style.muted
                Layout.leftMargin: Style.cardPadding
                Layout.topMargin: Style.spacingSmallPlus
                Layout.bottomMargin: Style.spacingSmallPlus
                Accessible.ignored: true
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.border }

            GridLayout {
                id: choicesGrid
                Layout.fillWidth: true
                Layout.margins: Style.cardPadding
                Layout.topMargin: Style.spacingSmallPlus
                Layout.bottomMargin: Style.spacingSmallPlus
                columns: 2
                columnSpacing: Style.formColumnSpacing
                rowSpacing: Style.spacingTiny

                SummaryLabel {
                    id: osLabel
                    text: qsTr("Image")
                    Layout.preferredWidth: Style.scaled(110)
                    Accessible.name: text + ": " + osValue.text
                }
                SummaryValue {
                    id: osValue
                    text: wizardContainer.selectedOsName || CommonStrings.noImageSelected
                }

                SummaryLabel {
                    id: storageLabel
                    text: qsTr("Storage")
                    Accessible.name: text + ": " + storageValue.text
                }
                SummaryValue {
                    id: storageValue
                    text: wizardContainer.selectedStorageName || CommonStrings.noStorageSelected
                }

                SummaryLabel {
                    id: configLabel
                    text: qsTr("Configuration")
                    Accessible.name: text + ": " + configValue.text
                }
                SummaryValue {
                    id: configValue
                    text: wizardContainer.eveConfigSummary()
                }
            }
        }

        // Next step for the person holding the drive
        Text {
            Layout.fillWidth: true
            text: qsTr("Boot the target device from this drive to install EVE-OS.")
            font.pointSize: Style.fontSizeDescription
            font.family: Style.fontFamily
            color: Style.muted
            wrapMode: Text.WordWrap
        }

        Item { Layout.fillHeight: true }
    }
    ]
    
    // Custom button container - network info is automatically added by WizardStepBase
    customButtonContainer: [
        Item {
            Layout.fillWidth: true
        },
        
        ImButton {
            id: writeAnotherButton
            text: qsTr("Write another")
            accessibleDescription: qsTr("Return to storage selection to write the same image to another storage device")
            enabled: true
            activeFocusOnTab: true
            Layout.minimumWidth: Style.buttonWidthMinimum
            Layout.preferredHeight: Style.buttonHeightStandard
            onClicked: {
                // Return to storage selection to write the same image to another SD card
                // This preserves device, OS, and customization settings
                wizardContainer.resetToWriteStep()
            }
        },
        
        ImButtonRed {
            id: finishButton
            text: imageWriter.isEmbeddedMode() ? qsTr("Reboot") : CommonStrings.finish
            accessibleDescription: imageWriter.isEmbeddedMode() ? qsTr("Reboot the system to apply changes") : qsTr("Close EVE Imager and exit the application")
            enabled: true
            activeFocusOnTab: true
            Layout.minimumWidth: Style.buttonWidthMinimum
            Layout.preferredHeight: Style.buttonHeightStandard
            onClicked: {
                if (imageWriter.isEmbeddedMode()) {
                    imageWriter.reboot()
                } else {
                    // Close the application
                    // Advanced options settings are already saved
                    Qt.quit()
                }
            }
        }
    ]
    
    Component.onCompleted: {
        // Register the result and the summary as focus groups
        registerFocusGroup("choices", function() {
            return [choicesHeading, ejectInstruction, osLabel, storageLabel, configLabel]
        }, 0)

        // Register custom buttons as the last focus group
        registerFocusGroup("buttons", function() {
            return [writeAnotherButton, finishButton]
        }, 3)
        
        // Ensure focus order is built after custom buttons are fully instantiated
        Qt.callLater(function() {
            rebuildFocusOrder()
        })
    }

} 
