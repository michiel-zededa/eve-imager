/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 ZEDEDA, Inc.
 *
 * Step 2 — EVE OS device configuration.
 */

pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../qmlcomponents"

import RpiImager

WizardStepBase {
    id: root

    required property ImageWriter imageWriter
    required property var wizardContainer

    title: qsTr("Device configuration (optional)")
    subtitle: qsTr("Everything on this page is optional — skip it entirely to write a plain EVE OS image. Any values you fill in will be written to the config partition on the USB drive before it is ejected.")

    showBackButton: true
    showNextButton: true
    nextButtonEnabled: true

    // ── Helper to update a single key in the eveConfig map ───────────────────
    function setCfg(key, value) {
        var c = root.wizardContainer.eveConfig
        c[key] = value
        root.wizardContainer.eveConfig = c
    }

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

                // ── Skip banner ───────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: Style.spacingSmall
                    color: Style.zededaLightBlue
                    radius: Style.sectionBorderRadius
                    height: skipBannerText.implicitHeight + Style.spacingSmall * 2

                    Text {
                        id: skipBannerText
                        anchors {
                            left: parent.left; right: parent.right
                            top: parent.top; margins: Style.spacingSmall
                        }
                        text: qsTr("All fields below are optional. Click Next to skip and write a plain image.")
                        font.family: Style.fontFamily
                        font.pointSize: Style.fontSizeDescription
                        color: Style.zededaNavy
                        wrapMode: Text.WordWrap
                    }
                }

                // ── Controller ────────────────────────────────────────────────
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
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Style.formRowSpacing

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.spacingSmall
                            WizardFormLabel {
                                text: qsTr("Controller URL")
                                Layout.preferredWidth: Style.scaled(140)
                            }
                            ImTextField {
                                id: controllerUrlField
                                Layout.fillWidth: true
                                placeholderText: qsTr("e.g. zedcloud.zededa.net  (optional)")
                                text: root.wizardContainer.eveConfig.controllerUrl
                                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhUrlCharactersOnly
                                onTextChanged: root.setCfg("controllerUrl", text)
                            }
                        }

                    }
                }

                // ── Networking ────────────────────────────────────────────────
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
                                    if (checked) root.setCfg("networkMode", "dhcp")
                                }
                            }

                            RadioButton {
                                id: staticRadio
                                text: qsTr("Static IP")
                                checked: root.wizardContainer.eveConfig.networkMode === "static"
                                font.family: Style.fontFamily
                                font.pointSize: Style.fontSizeFormLabel
                                onCheckedChanged: {
                                    if (checked) root.setCfg("networkMode", "static")
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
                                WizardFormLabel { text: qsTr("IP address"); Layout.preferredWidth: Style.scaled(140) }
                                ImTextField {
                                    Layout.fillWidth: true
                                    placeholderText: qsTr("e.g. 192.168.1.100/24")
                                    text: root.wizardContainer.eveConfig.staticIp
                                    onTextChanged: root.setCfg("staticIp", text)
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.spacingSmall
                                WizardFormLabel { text: qsTr("Gateway"); Layout.preferredWidth: Style.scaled(140) }
                                ImTextField {
                                    Layout.fillWidth: true
                                    placeholderText: qsTr("e.g. 192.168.1.1")
                                    text: root.wizardContainer.eveConfig.gateway
                                    onTextChanged: root.setCfg("gateway", text)
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.spacingSmall
                                WizardFormLabel { text: qsTr("DNS server"); Layout.preferredWidth: Style.scaled(140) }
                                ImTextField {
                                    Layout.fillWidth: true
                                    placeholderText: qsTr("e.g. 8.8.8.8")
                                    text: root.wizardContainer.eveConfig.dns
                                    onTextChanged: root.setCfg("dns", text)
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.spacingSmall
                            WizardFormLabel { text: qsTr("HTTP proxy"); Layout.preferredWidth: Style.scaled(140) }
                            ImTextField {
                                Layout.fillWidth: true
                                placeholderText: qsTr("http://proxy.example.com:3128  (optional)")
                                text: root.wizardContainer.eveConfig.proxyUrl
                                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhUrlCharactersOnly
                                onTextChanged: root.setCfg("proxyUrl", text)
                            }
                        }

                        WizardDescriptionText {
                            text: qsTr("Leave as DHCP if you have no static IP or proxy requirements.")
                            Layout.fillWidth: true
                        }
                    }
                }

                // ── WiFi ──────────────────────────────────────────────────────
                Text {
                    text: qsTr("WiFi")
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
                            text: qsTr("Configure a WiFi network for EVE to use on first boot. "
                                       + "Leave blank to use wired Ethernet only.")
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.spacingSmall
                            WizardFormLabel { text: qsTr("SSID"); Layout.preferredWidth: Style.scaled(140) }
                            ImTextField {
                                Layout.fillWidth: true
                                placeholderText: qsTr("Network name  (optional)")
                                text: root.wizardContainer.eveConfig.wifiSsid
                                inputMethodHints: Qt.ImhNoPredictiveText
                                onTextChanged: root.setCfg("wifiSsid", text)
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.spacingSmall
                            WizardFormLabel { text: qsTr("Password"); Layout.preferredWidth: Style.scaled(140) }
                            ImTextField {
                                Layout.fillWidth: true
                                placeholderText: qsTr("WPA2 passphrase  (optional)")
                                text: root.wizardContainer.eveConfig.wifiPassword
                                echoMode: TextInput.Password
                                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
                                onTextChanged: root.setCfg("wifiPassword", text)
                            }
                        }
                    }
                }

                // ── Installation ──────────────────────────────────────────────
                Text {
                    text: qsTr("Installation")
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
                            text: qsTr("Control which disks EVE installs onto. Leave blank to use the installer's defaults. "
                                       + "Use Linux disk names without /dev/ prefix (e.g. nvme0n1, sda).")
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.spacingSmall
                            WizardFormLabel {
                                text: qsTr("EVE install disk")
                                Layout.preferredWidth: Style.scaled(140)
                            }
                            ImTextField {
                                Layout.fillWidth: true
                                placeholderText: qsTr("e.g. nvme0n1  (optional, auto-detected if blank)")
                                text: root.wizardContainer.eveConfig.installDisk
                                inputMethodHints: Qt.ImhNoPredictiveText
                                onTextChanged: root.setCfg("installDisk", text)
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.spacingSmall
                            WizardFormLabel {
                                text: qsTr("/persist disk")
                                Layout.preferredWidth: Style.scaled(140)
                            }
                            ImTextField {
                                Layout.fillWidth: true
                                placeholderText: qsTr("e.g. sda  (optional, same disk as EVE if blank)")
                                text: root.wizardContainer.eveConfig.persistDisk
                                inputMethodHints: Qt.ImhNoPredictiveText
                                onTextChanged: root.setCfg("persistDisk", text)
                            }
                        }

                        CheckBox {
                            id: rebootCheckbox
                            text: qsTr("Reboot automatically after installation completes")
                            checked: root.wizardContainer.eveConfig.rebootAfterInstall
                            font.family: Style.fontFamily
                            font.pointSize: Style.fontSizeFormLabel
                            onCheckedChanged: root.setCfg("rebootAfterInstall", checked)
                        }
                    }
                }

                Item { height: Style.spacingLarge }
            }
        }
    ] // content:

}
