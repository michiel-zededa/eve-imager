/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 ZEDEDA, Inc.
 *
 * Step 2 — EVE OS device configuration.
 *
 * Phase 1: full UI scaffold wired to wizardContainer.eveConfig.
 * Phase 3: hook into EveConfigurator C++ for actual partition injection.
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../qmlcomponents"

import RpiImager

WizardStepBase {
    id: root

    required property ImageWriter imageWriter
    required property var wizardContainer

    title: qsTr("Device configuration")
    subtitle: qsTr("All fields are optional — settings are written into the EVE OS config partition before flashing.")

    showBackButton: true
    showNextButton: true
    nextButtonEnabled: true

    content: [
        Flickable {
            anchors.fill: parent
            contentWidth: parent.width
            contentHeight: formColumn.implicitHeight + Style.spacingLarge
            clip: true
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: formColumn
                width: parent.width
                spacing: Style.spacingMedium

                // ── Controller ────────────────────────────────────────────
                Text {
                    text: qsTr("Controller")
                    font.pointSize: Style.fontSizeHeading
                    font.family: Style.fontFamilyBold
                    font.bold: true
                    color: Style.zededaNavy
                    Layout.fillWidth: true
                    Layout.topMargin: Style.spacingSmall
                }

                WizardSectionContainer {
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.spacingSmall
                        WizardFormLabel {
                            text: qsTr("Controller URL")
                            Layout.preferredWidth: Style.scaled(130)
                        }
                        ImTextField {
                            id: controllerUrlField
                            Layout.fillWidth: true
                            placeholderText: qsTr("e.g. zedcloud.zededa.net")
                            text: root.wizardContainer.eveConfig.controllerUrl
                            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhUrlCharactersOnly
                            onTextChanged: {
                                var cfg = root.wizardContainer.eveConfig
                                cfg.controllerUrl = text
                                root.wizardContainer.eveConfig = cfg
                            }
                        }
                    }
                }

                // ── Networking ────────────────────────────────────────────
                Text {
                    text: qsTr("Networking")
                    font.pointSize: Style.fontSizeHeading
                    font.family: Style.fontFamilyBold
                    font.bold: true
                    color: Style.zededaNavy
                    Layout.fillWidth: true
                    Layout.topMargin: Style.spacingSmall
                }

                WizardSectionContainer {
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Style.formRowSpacing

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.spacingLarge

                            RadioButton {
                                id: dhcpRadio
                                text: qsTr("DHCP (automatic)")
                                checked: root.wizardContainer.eveConfig.networkMode === "dhcp"
                                font.family: Style.fontFamily
                                font.pointSize: Style.fontSizeFormLabel
                                onCheckedChanged: {
                                    if (checked) {
                                        var cfg = root.wizardContainer.eveConfig
                                        cfg.networkMode = "dhcp"
                                        root.wizardContainer.eveConfig = cfg
                                    }
                                }
                            }

                            RadioButton {
                                id: staticRadio
                                text: qsTr("Static IP")
                                checked: root.wizardContainer.eveConfig.networkMode === "static"
                                font.family: Style.fontFamily
                                font.pointSize: Style.fontSizeFormLabel
                                onCheckedChanged: {
                                    if (checked) {
                                        var cfg = root.wizardContainer.eveConfig
                                        cfg.networkMode = "static"
                                        root.wizardContainer.eveConfig = cfg
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Style.formRowSpacing
                            visible: staticRadio.checked

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.spacingSmall
                                WizardFormLabel { text: qsTr("IP address"); Layout.preferredWidth: Style.scaled(130) }
                                ImTextField {
                                    Layout.fillWidth: true
                                    placeholderText: qsTr("e.g. 192.168.1.100/24")
                                    text: root.wizardContainer.eveConfig.staticIp
                                    onTextChanged: { var c = root.wizardContainer.eveConfig; c.staticIp = text; root.wizardContainer.eveConfig = c }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.spacingSmall
                                WizardFormLabel { text: qsTr("Gateway"); Layout.preferredWidth: Style.scaled(130) }
                                ImTextField {
                                    Layout.fillWidth: true
                                    placeholderText: qsTr("e.g. 192.168.1.1")
                                    text: root.wizardContainer.eveConfig.gateway
                                    onTextChanged: { var c = root.wizardContainer.eveConfig; c.gateway = text; root.wizardContainer.eveConfig = c }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.spacingSmall
                                WizardFormLabel { text: qsTr("DNS server"); Layout.preferredWidth: Style.scaled(130) }
                                ImTextField {
                                    Layout.fillWidth: true
                                    placeholderText: qsTr("e.g. 8.8.8.8")
                                    text: root.wizardContainer.eveConfig.dns
                                    onTextChanged: { var c = root.wizardContainer.eveConfig; c.dns = text; root.wizardContainer.eveConfig = c }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.spacingSmall
                            WizardFormLabel { text: qsTr("HTTP proxy"); Layout.preferredWidth: Style.scaled(130) }
                            ImTextField {
                                Layout.fillWidth: true
                                placeholderText: qsTr("http://proxy.example.com:3128  (optional)")
                                text: root.wizardContainer.eveConfig.proxyUrl
                                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhUrlCharactersOnly
                                onTextChanged: { var c = root.wizardContainer.eveConfig; c.proxyUrl = text; root.wizardContainer.eveConfig = c }
                            }
                        }
                    }
                }

                // ── Device identity ───────────────────────────────────────
                Text {
                    text: qsTr("Device identity")
                    font.pointSize: Style.fontSizeHeading
                    font.family: Style.fontFamilyBold
                    font.bold: true
                    color: Style.zededaNavy
                    Layout.fillWidth: true
                    Layout.topMargin: Style.spacingSmall
                }

                WizardSectionContainer {
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Style.formRowSpacing

                        WizardDescriptionText {
                            text: qsTr("Optional onboarding certificate, private key, and soft serial number. "
                                       + "Written into the config partition before flashing.")
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.spacingSmall
                            WizardFormLabel { text: qsTr("Certificate (.pem)"); Layout.preferredWidth: Style.scaled(130) }
                            ImTextField {
                                id: certPathField
                                Layout.fillWidth: true
                                readOnly: true
                                placeholderText: qsTr("onboard.cert.pem  (optional)")
                                text: root.wizardContainer.eveConfig.onboardCertPath
                            }
                            ImButton { text: qsTr("Browse…"); onClicked: certFilePicker.open() }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.spacingSmall
                            WizardFormLabel { text: qsTr("Private key (.pem)"); Layout.preferredWidth: Style.scaled(130) }
                            ImTextField {
                                id: keyPathField
                                Layout.fillWidth: true
                                readOnly: true
                                placeholderText: qsTr("onboard.key.pem  (optional)")
                                text: root.wizardContainer.eveConfig.onboardKeyPath
                            }
                            ImButton { text: qsTr("Browse…"); onClicked: keyFilePicker.open() }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.spacingSmall
                            WizardFormLabel { text: qsTr("Device serial"); Layout.preferredWidth: Style.scaled(130) }
                            ImTextField {
                                Layout.fillWidth: true
                                placeholderText: qsTr("Soft serial number  (optional)")
                                text: root.wizardContainer.eveConfig.deviceSerial
                                onTextChanged: { var c = root.wizardContainer.eveConfig; c.deviceSerial = text; root.wizardContainer.eveConfig = c }
                            }
                        }
                    }
                }

                Item { height: Style.spacingLarge }
            }
        }
    ] // content:

    // File dialogs — outside content[] so they aren't clipped
    ImFileDialog {
        id: certFilePicker
        parent: Overlay.overlay
        anchors.centerIn: parent
        title: qsTr("Select onboarding certificate")
        nameFilters: ["PEM files (*.pem *.crt)", "All files (*)"]
        onAccepted: {
            var path = selectedFile.toString().replace(/^(file:\/{2,3})/, "")
            var cfg = root.wizardContainer.eveConfig
            cfg.onboardCertPath = path
            root.wizardContainer.eveConfig = cfg
            certPathField.text = path
        }
    }

    ImFileDialog {
        id: keyFilePicker
        parent: Overlay.overlay
        anchors.centerIn: parent
        title: qsTr("Select onboarding private key")
        nameFilters: ["PEM files (*.pem *.key)", "All files (*)"]
        onAccepted: {
            var path = selectedFile.toString().replace(/^(file:\/{2,3})/, "")
            var cfg = root.wizardContainer.eveConfig
            cfg.onboardKeyPath = path
            root.wizardContainer.eveConfig = cfg
            keyPathField.text = path
        }
    }
}
