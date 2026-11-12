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

    title: qsTr("Device configuration")
    subtitle: qsTr("Optional. Anything you fill in is written to the config partition of the USB drive.")

    showBackButton: true
    showNextButton: true
    nextButtonEnabled: true

    // ── Helper to update a single key in the eveConfig map ───────────────────
    function setCfg(key, value) {
        var c = root.wizardContainer.eveConfig
        c[key] = value
        root.wizardContainer.eveConfig = c
    }

    // Width of the label column in the form rows
    readonly property int labelWidth: Style.scaled(130)

    component SectionTitle: Text {
        font.pointSize: Style.fontSizeHeading
        font.family: Style.fontFamily
        font.weight: Style.fontWeightSemiBold
        color: Style.text
        Layout.fillWidth: true
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }

    component FormRow: RowLayout {
        property alias label: rowLabel.text
        Layout.fillWidth: true
        spacing: Style.spacingSmall
        WizardFormLabel {
            id: rowLabel
            Layout.preferredWidth: root.labelWidth
        }
    }

    content: [
        Flickable {
            id: formFlickable
            anchors.fill: parent
            contentWidth: width
            contentHeight: formColumn.implicitHeight + Style.spacingSmall
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ImScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: formColumn
                // Leave room for the scroll bar when there is one
                width: parent.width - (formFlickable.contentHeight > formFlickable.height ? Style.scrollBarWidth + Style.spacingXSmall : 0)
                spacing: Style.spacingSmallPlus

                // ── Controller ────────────────────────────────────────────────
                ImCard {
                    Layout.fillWidth: true
                    spacing: Style.spacingSmallPlus

                    SectionTitle { text: qsTr("Controller") }

                    FormRow {
                        label: qsTr("Controller URL")
                        ImTextField {
                            id: controllerUrlField
                            Layout.fillWidth: true
                            placeholderText: qsTr("e.g. zedcloud.zededa.net")
                            text: root.wizardContainer.eveConfig.controllerUrl
                            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhUrlCharactersOnly
                            Accessible.name: qsTr("Controller URL")
                            onTextChanged: root.setCfg("controllerUrl", text)
                        }
                    }
                }

                // ── Networking ────────────────────────────────────────────────
                ImCard {
                    Layout.fillWidth: true
                    spacing: Style.spacingSmallPlus

                    SectionTitle { text: qsTr("Networking") }

                    FormRow {
                        label: qsTr("Address")

                        ImRadioButton {
                            id: dhcpRadio
                            text: qsTr("DHCP (automatic)")
                            checked: root.wizardContainer.eveConfig.networkMode !== "static"
                            onToggled: if (checked) root.setCfg("networkMode", "dhcp")
                        }

                        ImRadioButton {
                            id: staticRadio
                            text: qsTr("Static IP")
                            checked: root.wizardContainer.eveConfig.networkMode === "static"
                            onToggled: if (checked) root.setCfg("networkMode", "static")
                        }

                        Item { Layout.fillWidth: true }
                    }

                    FormRow {
                        label: qsTr("IP address")
                        visible: staticRadio.checked
                        ImTextField {
                            Layout.fillWidth: true
                            placeholderText: qsTr("e.g. 192.168.1.100/24")
                            text: root.wizardContainer.eveConfig.staticIp
                            Accessible.name: qsTr("IP address")
                            onTextChanged: root.setCfg("staticIp", text)
                        }
                    }

                    FormRow {
                        label: qsTr("Gateway")
                        visible: staticRadio.checked
                        ImTextField {
                            Layout.fillWidth: true
                            placeholderText: qsTr("e.g. 192.168.1.1")
                            text: root.wizardContainer.eveConfig.gateway
                            Accessible.name: qsTr("Gateway")
                            onTextChanged: root.setCfg("gateway", text)
                        }
                    }

                    FormRow {
                        label: qsTr("DNS server")
                        visible: staticRadio.checked
                        ImTextField {
                            Layout.fillWidth: true
                            placeholderText: qsTr("e.g. 8.8.8.8")
                            text: root.wizardContainer.eveConfig.dns
                            Accessible.name: qsTr("DNS server")
                            onTextChanged: root.setCfg("dns", text)
                        }
                    }

                    FormRow {
                        label: qsTr("HTTP proxy")
                        ImTextField {
                            Layout.fillWidth: true
                            placeholderText: qsTr("e.g. http://proxy.example.com:3128")
                            text: root.wizardContainer.eveConfig.proxyUrl
                            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhUrlCharactersOnly
                            Accessible.name: qsTr("HTTP proxy")
                            onTextChanged: root.setCfg("proxyUrl", text)
                        }
                    }
                }

                // ── WiFi ──────────────────────────────────────────────────────
                ImCard {
                    Layout.fillWidth: true
                    spacing: Style.spacingSmallPlus

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Style.spacingXXSmall
                        SectionTitle { text: qsTr("WiFi") }
                        WizardDescriptionText {
                            text: qsTr("A WiFi network for EVE to use on first boot. Leave blank to use wired Ethernet only.")
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }

                    FormRow {
                        label: qsTr("SSID")
                        ImTextField {
                            Layout.fillWidth: true
                            placeholderText: qsTr("Network name")
                            text: root.wizardContainer.eveConfig.wifiSsid
                            inputMethodHints: Qt.ImhNoPredictiveText
                            Accessible.name: qsTr("WiFi SSID")
                            onTextChanged: root.setCfg("wifiSsid", text)
                        }
                    }

                    FormRow {
                        label: qsTr("Password")
                        ImTextField {
                            Layout.fillWidth: true
                            placeholderText: qsTr("WPA2 passphrase")
                            text: root.wizardContainer.eveConfig.wifiPassword
                            echoMode: TextInput.Password
                            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
                            Accessible.name: qsTr("WiFi password")
                            onTextChanged: root.setCfg("wifiPassword", text)
                        }
                    }
                }

                // ── Installation ──────────────────────────────────────────────
                ImCard {
                    Layout.fillWidth: true
                    spacing: Style.spacingSmallPlus

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Style.spacingXXSmall
                        SectionTitle { text: qsTr("Installation") }
                        WizardDescriptionText {
                            text: qsTr("Which disks EVE installs onto. Leave blank to use the installer's defaults. "
                                       + "Use Linux disk names without the /dev/ prefix (e.g. nvme0n1, sda).")
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }

                    FormRow {
                        label: qsTr("EVE install disk")
                        ImTextField {
                            Layout.fillWidth: true
                            placeholderText: qsTr("e.g. nvme0n1 (auto-detected if blank)")
                            text: root.wizardContainer.eveConfig.installDisk
                            inputMethodHints: Qt.ImhNoPredictiveText
                            Accessible.name: qsTr("EVE install disk")
                            onTextChanged: root.setCfg("installDisk", text)
                        }
                    }

                    FormRow {
                        label: qsTr("/persist disk")
                        ImTextField {
                            Layout.fillWidth: true
                            placeholderText: qsTr("e.g. sda (same disk as EVE if blank)")
                            text: root.wizardContainer.eveConfig.persistDisk
                            inputMethodHints: Qt.ImhNoPredictiveText
                            Accessible.name: qsTr("/persist disk")
                            onTextChanged: root.setCfg("persistDisk", text)
                        }
                    }

                    ImCheckBox {
                        id: rebootCheckbox
                        Layout.fillWidth: true
                        text: qsTr("Reboot automatically after installation completes")
                        checked: root.wizardContainer.eveConfig.rebootAfterInstall
                        onToggled: root.setCfg("rebootAfterInstall", checked)
                    }
                }

                Item { implicitHeight: Style.spacingXSmall }
            }
        }
    ] // content:

}
