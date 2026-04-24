/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 ZEDEDA, Inc.
 *
 * Step 0 — EVE OS version / image selection.
 *
 * Phase 2: live GitHub releases via EveReleaseFetcher with cascading combos.
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

    title: qsTr("Select EVE OS image")
    subtitle: qsTr("Choose a release to download, or select a locally downloaded image file.")

    showBackButton: false
    showNextButton: true
    nextButtonEnabled: {
        if (tabBar.currentIndex === 0) {
            return versionCombo.currentIndex >= 0
                   && archCombo.currentIndex >= 0
                   && hvCombo.currentIndex >= 0
                   && platformCombo.currentIndex >= 0
                   && !noAssetWarning.visible
                   && !releaseFetcher.loading
        } else {
            return localPathField.text.length > 0
        }
    }

    // ── EveReleaseFetcher instance ─────────────────────────────────────────
    EveReleaseFetcher {
        id: releaseFetcher

        onReleasesReady: {
            // Restore prior version selection after a fetch (initial load only).
            var savedVersion = root.wizardContainer.eveVersion
            if (savedVersion.length > 0) {
                var idx = releaseFetcher.versions.indexOf(savedVersion)
                if (idx >= 0) {
                    versionCombo.currentIndex = idx
                    return   // _refreshArchModel etc. will fire from onCurrentIndexChanged
                }
            }
            if (releaseFetcher.versions.length > 0 && versionCombo.currentIndex < 0) {
                versionCombo.currentIndex = 0
            }
            root._refreshArchModel()
        }

        onFetchFailed: function(msg) {
            fetchErrorText.text = qsTr("Could not load releases: %1").arg(msg)
        }
    }

    // ── Cascading model arrays ─────────────────────────────────────────────
    property var archModel: []
    property var hvModel: []
    property var platformModel: []

    function _refreshArchModel() {
        var v = versionCombo.currentIndex >= 0 ? releaseFetcher.versions[versionCombo.currentIndex] : ""
        root.archModel = v.length > 0 ? releaseFetcher.archesForVersion(v) : []
        // Preserve prior selection if still available
        var savedArch = root.wizardContainer.eveArch
        var idx = root.archModel.indexOf(savedArch)
        archCombo.currentIndex = (idx >= 0) ? idx : (root.archModel.length > 0 ? 0 : -1)
        root._refreshHvModel()
    }

    function _refreshHvModel() {
        var v = versionCombo.currentIndex >= 0 ? releaseFetcher.versions[versionCombo.currentIndex] : ""
        var a = archCombo.currentIndex >= 0 ? root.archModel[archCombo.currentIndex] : ""
        root.hvModel = (v.length > 0 && a.length > 0) ? releaseFetcher.hypervisorsFor(v, a) : []
        var savedHv = root.wizardContainer.eveHypervisor
        var idx = root.hvModel.indexOf(savedHv)
        hvCombo.currentIndex = (idx >= 0) ? idx : (root.hvModel.length > 0 ? 0 : -1)
        root._refreshPlatformModel()
    }

    function _refreshPlatformModel() {
        var v = versionCombo.currentIndex >= 0 ? releaseFetcher.versions[versionCombo.currentIndex] : ""
        var a = archCombo.currentIndex >= 0 ? root.archModel[archCombo.currentIndex] : ""
        var h = hvCombo.currentIndex >= 0 ? root.hvModel[hvCombo.currentIndex] : ""
        root.platformModel = (v.length > 0 && a.length > 0 && h.length > 0)
                             ? releaseFetcher.platformsFor(v, a, h) : []
        var savedPlatform = root.wizardContainer.evePlatform
        var idx = root.platformModel.indexOf(savedPlatform)
        platformCombo.currentIndex = (idx >= 0) ? idx : (root.platformModel.length > 0 ? 0 : -1)
        // Eagerly sync all wizard state so the Writing step always sees fresh values
        root._syncWizardDownloadState()
    }

    function _syncWizardDownloadState() {
        var v = versionCombo.currentIndex >= 0 ? releaseFetcher.versions[versionCombo.currentIndex] : ""
        var a = archCombo.currentIndex >= 0 ? root.archModel[archCombo.currentIndex] : ""
        var h = hvCombo.currentIndex >= 0 ? root.hvModel[hvCombo.currentIndex] : ""
        var p = platformCombo.currentIndex >= 0 ? root.platformModel[platformCombo.currentIndex] : ""
        root.wizardContainer.eveVersion      = v
        root.wizardContainer.eveArch         = a
        root.wizardContainer.eveHypervisor   = h
        root.wizardContainer.evePlatform     = p
        var hasAll = v.length > 0 && a.length > 0 && h.length > 0 && p.length > 0
        root.wizardContainer.eveDownloadUrl  = hasAll ? releaseFetcher.downloadUrl(v, a, h, p) : ""
        root.wizardContainer.eveDownloadSize = hasAll ? releaseFetcher.downloadSize(v, a, h, p) : 0
        root.wizardContainer.eveIsIsoImage   = hasAll ? releaseFetcher.isIsoAsset(v, a, h, p) : false
        root.wizardContainer.selectedOsName  = hasAll
                                               ? qsTr("EVE OS %1 · %2/%3/%4").arg(v).arg(a).arg(h).arg(p) : ""
    }

    // ── Content ────────────────────────────────────────────────────────────
    content: [
        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Tab selector pinned to top
            TabBar {
                id: tabBar
                Layout.fillWidth: true
                font.family: Style.fontFamily
                font.pointSize: Style.fontSizeFormLabel

                TabButton {
                    text: qsTr("Download from GitHub")
                    font.family: Style.fontFamily
                }
                TabButton {
                    text: qsTr("Use local image file")
                    font.family: Style.fontFamily
                }
            }

            // Tab pages
            StackLayout {
                id: tabPages
                currentIndex: tabBar.currentIndex
                Layout.fillWidth: true
                Layout.fillHeight: true

                // ── Download pane ─────────────────────────────────────────
                ColumnLayout {
                    spacing: Style.formRowSpacing

                    Item { height: Style.spacingSmall }

                    // Loading / error banner
                    Rectangle {
                        id: statusBanner
                        Layout.fillWidth: true
                        color: releaseFetcher.fetchFailed ? "#fff3cd"
                                                          : Style.zededaLightBlue
                        radius: Style.sectionBorderRadius
                        height: bannerRow.implicitHeight + Style.spacingSmall * 2
                        visible: releaseFetcher.loading || fetchErrorText.text.length > 0

                        RowLayout {
                            id: bannerRow
                            anchors {
                                left: parent.left; right: parent.right
                                top: parent.top; margins: Style.spacingSmall
                            }
                            spacing: Style.spacingSmall

                            BusyIndicator {
                                running: releaseFetcher.loading
                                visible: releaseFetcher.loading
                                implicitWidth: Style.scaled(20)
                                implicitHeight: Style.scaled(20)
                            }

                            Text {
                                id: fetchErrorText
                                Layout.fillWidth: true
                                text: releaseFetcher.loading ? releaseFetcher.statusMessage : ""
                                font.family: Style.fontFamily
                                font.pointSize: Style.fontSizeDescription
                                color: Style.zededaNavy
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    // Version
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.spacingSmall
                        WizardFormLabel {
                            text: qsTr("Version")
                            Layout.preferredWidth: Style.scaled(110)
                        }
                        ImComboBox {
                            id: versionCombo
                            Layout.fillWidth: true
                            model: releaseFetcher.versions
                            enabled: !releaseFetcher.loading && count > 0
                            displayText: currentIndex >= 0 ? currentText : qsTr("Select version…")
                            onCurrentIndexChanged: root._refreshArchModel()
                        }
                    }

                    // Architecture
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.spacingSmall
                        WizardFormLabel {
                            text: qsTr("Architecture")
                            Layout.preferredWidth: Style.scaled(110)
                        }
                        ImComboBox {
                            id: archCombo
                            Layout.fillWidth: true
                            model: root.archModel
                            enabled: !releaseFetcher.loading && count > 0
                            displayText: currentIndex >= 0 ? currentText : qsTr("—")
                            onCurrentIndexChanged: root._refreshHvModel()
                        }
                    }

                    // Hypervisor
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.spacingSmall
                        WizardFormLabel {
                            text: qsTr("Hypervisor")
                            Layout.preferredWidth: Style.scaled(110)
                        }
                        ImComboBox {
                            id: hvCombo
                            Layout.fillWidth: true
                            model: root.hvModel
                            enabled: !releaseFetcher.loading && count > 0
                            displayText: currentIndex >= 0 ? currentText : qsTr("—")
                            onCurrentIndexChanged: root._refreshPlatformModel()
                        }
                    }

                    // Platform
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.spacingSmall
                        WizardFormLabel {
                            text: qsTr("Platform")
                            Layout.preferredWidth: Style.scaled(110)
                        }
                        ImComboBox {
                            id: platformCombo
                            Layout.fillWidth: true
                            model: root.platformModel
                            enabled: !releaseFetcher.loading && count > 0
                            displayText: currentIndex >= 0 ? currentText : qsTr("—")
                            onCurrentIndexChanged: root._syncWizardDownloadState()
                        }
                    }

                    // No-asset warning
                    Rectangle {
                        id: noAssetWarning
                        Layout.fillWidth: true
                        color: "#fff3cd"
                        radius: Style.sectionBorderRadius
                        height: noAssetText.implicitHeight + Style.spacingSmall * 2
                        visible: !releaseFetcher.loading
                                 && versionCombo.currentIndex >= 0
                                 && root.platformModel.length === 0

                        Text {
                            id: noAssetText
                            anchors {
                                left: parent.left; right: parent.right
                                top: parent.top; margins: Style.spacingSmall
                            }
                            text: qsTr("No installer images found for this combination.")
                            font.family: Style.fontFamily
                            font.pointSize: Style.fontSizeDescription
                            color: Style.formLabelErrorColor
                            wrapMode: Text.WordWrap
                        }
                    }

                    // Asset preview badge
                    Rectangle {
                        id: assetPreview
                        Layout.fillWidth: true
                        color: Style.zededaLightBlue
                        radius: Style.sectionBorderRadius
                        height: assetLabel.implicitHeight + Style.spacingSmall * 2
                        visible: !releaseFetcher.loading
                                 && versionCombo.currentIndex >= 0
                                 && archCombo.currentIndex >= 0
                                 && hvCombo.currentIndex >= 0
                                 && platformCombo.currentIndex >= 0
                                 && root.platformModel.length > 0

                        Text {
                            id: assetLabel
                            anchors {
                                left: parent.left; right: parent.right
                                top: parent.top; margins: Style.spacingSmall
                            }
                            text: {
                                if (!assetPreview.visible) return ""
                                var v = releaseFetcher.versions[versionCombo.currentIndex] || ""
                                var a = root.archModel[archCombo.currentIndex] || ""
                                var h = root.hvModel[hvCombo.currentIndex] || ""
                                var p = root.platformModel[platformCombo.currentIndex] || ""
                                var sz = releaseFetcher.downloadSize(v, a, h, p)
                                var szStr = sz > 0 ? " (" + (sz / (1024*1024*1024)).toFixed(2) + " GB)" : ""
                                var ext = releaseFetcher.isIsoAsset(v, a, h, p) ? "installer.iso" : "installer.raw"
                                return qsTr("Will download: %1.%2.%3.%4%5")
                                       .arg(a).arg(h).arg(p).arg(ext).arg(szStr)
                            }
                            font.family: Style.fontFamily
                            font.pointSize: Style.fontSizeDescription
                            color: Style.zededaNavy
                            wrapMode: Text.WordWrap
                        }
                    }

                    // ISO warning — config customization not supported for ISO assets
                    Rectangle {
                        id: isoWarning
                        Layout.fillWidth: true
                        color: "#fff3cd"
                        radius: Style.sectionBorderRadius
                        height: isoWarningText.implicitHeight + Style.spacingSmall * 2
                        visible: {
                            if (releaseFetcher.loading || root.platformModel.length === 0) return false
                            var v = versionCombo.currentIndex >= 0 ? releaseFetcher.versions[versionCombo.currentIndex] : ""
                            var a = archCombo.currentIndex >= 0 ? root.archModel[archCombo.currentIndex] : ""
                            var h = hvCombo.currentIndex >= 0 ? root.hvModel[hvCombo.currentIndex] : ""
                            var p = platformCombo.currentIndex >= 0 ? root.platformModel[platformCombo.currentIndex] : ""
                            return v.length > 0 && a.length > 0 && h.length > 0 && p.length > 0
                                   && releaseFetcher.isIsoAsset(v, a, h, p)
                        }

                        Text {
                            id: isoWarningText
                            anchors {
                                left: parent.left; right: parent.right
                                top: parent.top; margins: Style.spacingSmall
                            }
                            text: qsTr("Note: This combination is only available as an ISO image. "
                                       + "The image will be written to USB as a bootable installer, "
                                       + "but custom configuration (controller URL, network settings) "
                                       + "cannot be applied to ISO images.")
                            font.family: Style.fontFamily
                            font.pointSize: Style.fontSizeDescription
                            color: "#856404"
                            wrapMode: Text.WordWrap
                        }
                    }

                    Item { Layout.fillHeight: true }
                } // Download pane

                // ── Local image pane ──────────────────────────────────────
                ColumnLayout {
                    spacing: Style.formRowSpacing

                    Item { height: Style.spacingSmall }

                    WizardDescriptionText {
                        text: qsTr("Select a locally downloaded EVE OS installer image (.raw or .iso). "
                                   + "Config customization is supported for .raw images only.")
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.spacingSmall

                        ImTextField {
                            id: localPathField
                            Layout.fillWidth: true
                            placeholderText: qsTr("Path to .raw or .iso image file…")
                            readOnly: true
                            text: root.wizardContainer.eveLocalImagePath
                        }

                        ImButton {
                            text: qsTr("Browse…")
                            onClicked: localFilePicker.open()
                        }
                    }

                    Item { Layout.fillHeight: true }
                } // Local image pane
            } // StackLayout
        } // ColumnLayout (content root)
    ] // content:

    // File dialog — lives outside content[] so it's not clipped by the content area
    ImFileDialog {
        id: localFilePicker
        parent: Overlay.overlay
        anchors.centerIn: parent
        title: qsTr("Select EVE OS installer image")
        nameFilters: ["EVE OS installer images (*.raw *.iso)", "Raw disk images (*.raw)", "ISO images (*.iso)", "All files (*)"]
        onAccepted: {
            var path = selectedFile.toString().replace(/^(file:\/{2,3})/, "")
            root.wizardContainer.eveLocalImagePath = path
            root.wizardContainer.useLocalImage = true
            root.wizardContainer.eveIsIsoImage = path.toLowerCase().endsWith(".iso")
            root.wizardContainer.selectedOsName = qsTr("Local image: %1").arg(path.split("/").pop())
        }
    }

    Component.onCompleted: {
        releaseFetcher.fetchReleases()
    }

    // Sync wizard state when Next is clicked — state is already kept live by
    // _syncWizardDownloadState(), so this just sets the tab-dependent flags.
    function syncState() {
        if (tabBar.currentIndex === 0) {
            root.wizardContainer.useLocalImage = false
            root._syncWizardDownloadState()
        } else {
            root.wizardContainer.useLocalImage   = true
            root.wizardContainer.eveDownloadUrl  = ""
            root.wizardContainer.eveDownloadSize = 0
            root.wizardContainer.selectedOsName  = root.wizardContainer.eveLocalImagePath.length > 0
                ? qsTr("Local image: %1").arg(root.wizardContainer.eveLocalImagePath.split("/").pop())
                : ""
        }
    }
}
