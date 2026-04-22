/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 ZEDEDA, Inc.
 *
 * Step 2 — EVE OS device configuration.
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

                        // ── Advanced toggle ───────────────────────────────────
                        CheckBox {
                            id: showAdvancedCerts
                            text: qsTr("Advanced certificate options")
                            checked: false
                            font.family: Style.fontFamily
                            font.pointSize: Style.fontSizeFormLabel
                            Layout.topMargin: Style.spacingSmall
                        }

                        // ── Advanced: CA cert + onboarding certs ──────────────
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Style.formRowSpacing
                            visible: showAdvancedCerts.checked

                            // Subtle separator
                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Style.inputBorderColor
                                opacity: 0.5
                            }

                            WizardDescriptionText {
                                text: qsTr("Controller CA certificate — required only for self-hosted or private controller deployments. "
                                           + "Onboarding certificates allow pre-provisioning a device with a known identity; "
                                           + "the certificate must be pre-registered in your controller.")
                                Layout.fillWidth: true
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.spacingSmall
                                WizardFormLabel {
                                    text: qsTr("Controller CA cert")
                                    Layout.preferredWidth: Style.scaled(140)
                                }
                                ImTextField {
                                    id: rootCertField
                                    Layout.fillWidth: true
                                    readOnly: true
                                    placeholderText: qsTr("root-certificate.pem  (optional)")
                                    text: root.wizardContainer.eveConfig.rootCertPath
                                }
                                ImButton {
                                    text: qsTr("Browse…")
                                    onClicked: rootCertPicker.open()
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.spacingSmall
                                WizardFormLabel {
                                    text: qsTr("Onboard cert (.pem)")
                                    Layout.preferredWidth: Style.scaled(140)
                                }
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
                                WizardFormLabel {
                                    text: qsTr("Onboard key (.pem)")
                                    Layout.preferredWidth: Style.scaled(140)
                                }
                                ImTextField {
                                    id: keyPathField
                                    Layout.fillWidth: true
                                    readOnly: true
                                    placeholderText: qsTr("onboard.key.pem  (optional)")
                                    text: root.wizardContainer.eveConfig.onboardKeyPath
                                }
                                ImButton { text: qsTr("Browse…"); onClicked: keyFilePicker.open() }
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

                // ── SSH access ────────────────────────────────────────────────
                Text {
                    text: qsTr("SSH access")
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
                            text: qsTr("Add an SSH public key to enable debug console access on the device. "
                                       + "Paste the key below or load it from a file.")
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.spacingSmall

                            ScrollView {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.scaled(70)
                                clip: true

                                TextArea {
                                    id: authorizedKeysArea
                                    placeholderText: qsTr("ssh-ed25519 AAAA… user@host  (optional)")
                                    text: root.wizardContainer.eveConfig.authorizedKeys
                                    font.family: "Menlo, Monaco, Courier New, monospace"
                                    font.pointSize: Style.fontSizeDescription
                                    wrapMode: TextArea.Wrap
                                    onTextChanged: root.setCfg("authorizedKeys", text)
                                    background: Rectangle {
                                        color: Style.inputBackgroundColor
                                        border.color: authorizedKeysArea.activeFocus
                                                      ? Style.inputBorderFocusColor
                                                      : Style.inputBorderColor
                                        radius: Style.inputBorderRadius
                                    }
                                }
                            }

                            ImButton {
                                text: qsTr("Load file…")
                                onClicked: sshKeyFilePicker.open()
                                Layout.alignment: Qt.AlignTop
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

    // ── File dialogs ──────────────────────────────────────────────────────────

    ImFileDialog {
        id: rootCertPicker
        parent: Overlay.overlay
        anchors.centerIn: parent
        title: qsTr("Select controller CA certificate")
        nameFilters: ["PEM / CRT files (*.pem *.crt)", "All files (*)"]
        onAccepted: {
            var path = selectedFile.toString().replace(/^(file:\/{2,3})/, "")
            root.setCfg("rootCertPath", path)
            rootCertField.text = path
        }
    }

    ImFileDialog {
        id: certFilePicker
        parent: Overlay.overlay
        anchors.centerIn: parent
        title: qsTr("Select onboarding certificate")
        nameFilters: ["PEM files (*.pem *.crt)", "All files (*)"]
        onAccepted: {
            var path = selectedFile.toString().replace(/^(file:\/{2,3})/, "")
            root.setCfg("onboardCertPath", path)
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
            root.setCfg("onboardKeyPath", path)
            keyPathField.text = path
        }
    }

    ImFileDialog {
        id: sshKeyFilePicker
        parent: Overlay.overlay
        anchors.centerIn: parent
        title: qsTr("Select SSH public key")
        nameFilters: ["Public key files (*.pub)", "All files (*)"]
        onAccepted: {
            var xhr = new XMLHttpRequest()
            xhr.open("GET", selectedFile.toString())
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    var key = xhr.responseText.trim()
                    root.setCfg("authorizedKeys", key)
                    authorizedKeysArea.text = key
                }
            }
            xhr.send()
        }
    }
}
