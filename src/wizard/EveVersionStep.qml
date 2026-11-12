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

    title: qsTr("Select EVE-OS image")
    subtitle: qsTr("Choose a release to download, or select an image file you already have.")

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
                   // Wait for the image size lookup (one small request), so the
                   // next steps can check that the drive is large enough.
                   && !releaseFetcher.probingImageSize
        } else {
            return localPathField.text.length > 0
        }
    }

    // ── EveReleaseFetcher instance ─────────────────────────────────────────
    EveReleaseFetcher {
        id: releaseFetcher

        // The real (decompressed) size of the selected compressed image has
        // been read from the file's header.
        onImageSizeKnown: function(url, size) {
            if (url === root.wizardContainer.eveDownloadUrl) {
                root.wizardContainer.eveImageSize = size
            }
        }

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
            root.fetchError = qsTr("Could not load releases: %1").arg(msg)
        }
    }

    // Message shown when the release list could not be loaded
    property string fetchError: ""

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
        root.wizardContainer.eveIsCompressedImage = hasAll ? releaseFetcher.isCompressedAsset(v, a, h, p) : false
        root.wizardContainer.eveIsIsoImage   = hasAll ? releaseFetcher.isIsoAsset(v, a, h, p) : false
        // Size the image takes on the drive. For uncompressed assets that is
        // the download size. For compressed ones it has to be read from the
        // file itself: use the value if we already have it and (re)start the
        // lookup otherwise - onImageSizeKnown fills it in when it arrives.
        if (!hasAll) {
            root.wizardContainer.eveImageSize = 0
        } else if (root.wizardContainer.eveIsCompressedImage) {
            root.wizardContainer.eveImageSize = releaseFetcher.imageSize(root.wizardContainer.eveDownloadUrl)
            releaseFetcher.probeImageSize(root.wizardContainer.eveDownloadUrl)
        } else {
            root.wizardContainer.eveImageSize = root.wizardContainer.eveDownloadSize
        }
        root.wizardContainer.selectedOsName  = hasAll
                                               ? qsTr("EVE-OS %1 · %2/%3/%4").arg(v).arg(a).arg(h).arg(p) : ""
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
                spacing: Style.spacingTiny
                // A hairline under the tabs; the selected tab draws its accent
                // underline on top of it
                background: Item {
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Style.border
                    }
                }

                ImTabButton { text: qsTr("Download release") }
                ImTabButton { text: qsTr("Use local image file") }
            }

            // Tab pages
            StackLayout {
                id: tabPages
                currentIndex: tabBar.currentIndex
                Layout.fillWidth: true
                Layout.fillHeight: true

                // ── Download pane ─────────────────────────────────────────
                ColumnLayout {
                    spacing: Style.spacingSmallPlus

                    Item { implicitHeight: Style.spacingXSmall }

                    // Loading / error banner
                    ImBanner {
                        id: statusBanner
                        Layout.fillWidth: true
                        kind: releaseFetcher.fetchFailed ? "warn" : "info"
                        busy: releaseFetcher.loading
                        text: releaseFetcher.loading ? releaseFetcher.statusMessage : root.fetchError
                        visible: releaseFetcher.loading || root.fetchError.length > 0
                    }

                    ImCard {
                        id: selectionCard
                        Layout.fillWidth: true
                        padding: 0
                        spacing: 0

                        // The four selectors, two per row, label above control
                        GridLayout {
                            Layout.fillWidth: true
                            Layout.margins: Style.cardPadding
                            columns: 2
                            columnSpacing: Style.spacingLarge
                            rowSpacing: Style.spacingMedium
                            uniformCellWidths: true

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.scaled(6)
                                RowLayout {
                                    spacing: Style.spacingTiny
                                    WizardFormLabel {
                                        text: qsTr("Version")
                                        font.weight: Style.fontWeightMedium
                                    }
                                    ImPill {
                                        kind: "ok"
                                        text: qsTr("LTS")
                                        visible: versionCombo.currentIndex >= 0
                                                 && versionCombo.currentText.indexOf("-lts") >= 0
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                                ImComboBox {
                                    id: versionCombo
                                    Layout.fillWidth: true
                                    model: releaseFetcher.versions
                                    enabled: !releaseFetcher.loading && count > 0
                                    displayText: currentIndex >= 0 ? currentText : qsTr("Select version…")
                                    Accessible.name: qsTr("Version")
                                    onCurrentIndexChanged: root._refreshArchModel()
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.scaled(6)
                                WizardFormLabel {
                                    text: qsTr("Architecture")
                                    font.weight: Style.fontWeightMedium
                                    Layout.preferredHeight: Style.scaled(24)
                                    verticalAlignment: Text.AlignVCenter
                                }
                                ImComboBox {
                                    id: archCombo
                                    Layout.fillWidth: true
                                    model: root.archModel
                                    enabled: !releaseFetcher.loading && count > 0
                                    displayText: currentIndex >= 0 ? currentText : qsTr("—")
                                    Accessible.name: qsTr("Architecture")
                                    onCurrentIndexChanged: root._refreshHvModel()
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.scaled(6)
                                WizardFormLabel {
                                    text: qsTr("Hypervisor")
                                    font.weight: Style.fontWeightMedium
                                }
                                ImComboBox {
                                    id: hvCombo
                                    Layout.fillWidth: true
                                    model: root.hvModel
                                    enabled: !releaseFetcher.loading && count > 0
                                    displayText: currentIndex >= 0 ? currentText : qsTr("—")
                                    Accessible.name: qsTr("Hypervisor")
                                    onCurrentIndexChanged: root._refreshPlatformModel()
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.scaled(6)
                                WizardFormLabel {
                                    text: qsTr("Platform")
                                    font.weight: Style.fontWeightMedium
                                }
                                ImComboBox {
                                    id: platformCombo
                                    Layout.fillWidth: true
                                    model: root.platformModel
                                    enabled: !releaseFetcher.loading && count > 0
                                    displayText: currentIndex >= 0 ? currentText : qsTr("—")
                                    Accessible.name: qsTr("Platform")
                                    onCurrentIndexChanged: root._syncWizardDownloadState()
                                }
                            }
                        }

                        // Card footer: what will be downloaded
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: Style.border
                            visible: assetPreview.visible
                        }

                        RowLayout {
                            id: assetPreview
                            Layout.fillWidth: true
                            Layout.leftMargin: Style.cardPadding
                            Layout.rightMargin: Style.cardPadding
                            Layout.topMargin: Style.spacingSmallPlus
                            Layout.bottomMargin: Style.spacingSmallPlus
                            spacing: Style.spacingSmallPlus
                            visible: !releaseFetcher.loading
                                     && versionCombo.currentIndex >= 0
                                     && archCombo.currentIndex >= 0
                                     && hvCombo.currentIndex >= 0
                                     && platformCombo.currentIndex >= 0
                                     && root.platformModel.length > 0

                            readonly property string v: visible ? (releaseFetcher.versions[versionCombo.currentIndex] || "") : ""
                            readonly property string a: visible ? (root.archModel[archCombo.currentIndex] || "") : ""
                            readonly property string h: visible ? (root.hvModel[hvCombo.currentIndex] || "") : ""
                            readonly property string p: visible ? (root.platformModel[platformCombo.currentIndex] || "") : ""

                            Rectangle {
                                implicitWidth: Style.scaled(36)
                                implicitHeight: Style.scaled(36)
                                radius: Style.controlBorderRadius
                                color: Style.accentSoft
                                ImIcon {
                                    anchors.centerIn: parent
                                    name: "download"
                                    color: Style.accentText
                                    size: Style.scaled(18)
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.spacingXXSmall

                                Text {
                                    id: assetLabel
                                    Layout.fillWidth: true
                                    // Show the real asset name: it may be compressed
                                    // (.installer.raw.zst) rather than a plain .raw.
                                    text: {
                                        if (!assetPreview.visible) return ""
                                        var fileName = releaseFetcher.assetFileName(assetPreview.v, assetPreview.a, assetPreview.h, assetPreview.p)
                                        if (fileName.length === 0) {
                                            var ext = releaseFetcher.isIsoAsset(assetPreview.v, assetPreview.a, assetPreview.h, assetPreview.p)
                                                      ? "installer.iso" : "installer.raw"
                                            fileName = assetPreview.a + "." + assetPreview.h + "." + assetPreview.p + "." + ext
                                        }
                                        return fileName
                                    }
                                    font.family: Style.fontFamilyMono
                                    font.pointSize: Style.fontSizeDescription
                                    color: Style.text
                                    elide: Text.ElideMiddle
                                    Accessible.name: qsTr("Will download: %1").arg(text)
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        if (!assetPreview.visible) return ""
                                        var sz = releaseFetcher.downloadSize(assetPreview.v, assetPreview.a, assetPreview.h, assetPreview.p)
                                        return sz > 0 ? qsTr("%1 GB download").arg((sz / (1024*1024*1024)).toFixed(2))
                                                      : qsTr("Download")
                                    }
                                    font.family: Style.fontFamily
                                    font.pointSize: Style.fontSizeDescription
                                    color: Style.muted
                                    elide: Text.ElideRight
                                }
                            }

                            // Compressed images unpack to much more than the
                            // download: say how large a drive is needed.
                            ImPill {
                                kind: "info"
                                visible: text.length > 0
                                text: {
                                    var onDrive = root.wizardContainer.eveImageSize
                                    if (root.wizardContainer.eveIsCompressedImage && onDrive > 0)
                                        return qsTr("Needs a drive of at least %1").arg(root.imageWriter.formatSize(onDrive))
                                    if (releaseFetcher.probingImageSize)
                                        return qsTr("Checking the image size…")
                                    return ""
                                }
                            }
                        }
                    }

                    // No-asset warning
                    ImBanner {
                        id: noAssetWarning
                        Layout.fillWidth: true
                        kind: "err"
                        text: qsTr("No installer images found for this combination.")
                        visible: !releaseFetcher.loading
                                 && versionCombo.currentIndex >= 0
                                 && root.platformModel.length === 0
                    }

                    // ISO warning — config customization not supported for ISO assets
                    ImBanner {
                        id: isoWarning
                        Layout.fillWidth: true
                        kind: "warn"
                        text: qsTr("This combination is only available as an ISO image. "
                                   + "It will be written to USB as a bootable installer, "
                                   + "but custom configuration (controller URL, network settings) "
                                   + "cannot be applied to ISO images.")
                        visible: assetPreview.visible
                                 && releaseFetcher.isIsoAsset(assetPreview.v, assetPreview.a, assetPreview.h, assetPreview.p)
                    }

                    Item { Layout.fillHeight: true }
                } // Download pane

                // ── Local image pane ──────────────────────────────────────
                ColumnLayout {
                    spacing: Style.spacingSmallPlus

                    Item { implicitHeight: Style.spacingXSmall }

                    ImCard {
                        Layout.fillWidth: true
                        spacing: Style.spacingSmall

                        WizardFormLabel {
                            text: qsTr("Image file")
                            font.weight: Style.fontWeightMedium
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

                        WizardDescriptionText {
                            text: qsTr("Select an EVE-OS installer image you already downloaded (.raw or .iso). "
                                       + "Configuration can be added to .raw images only.")
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
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
        title: qsTr("Select EVE-OS installer image")
        nameFilters: ["EVE-OS installer images (*.raw *.iso)", "Raw disk images (*.raw)", "ISO images (*.iso)", "All files (*)"]
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
            root.wizardContainer.eveIsCompressedImage = false
            root.wizardContainer.eveImageSize = 0   // local files are sized by the writer itself
            root.wizardContainer.selectedOsName  = root.wizardContainer.eveLocalImagePath.length > 0
                ? qsTr("Local image: %1").arg(root.wizardContainer.eveLocalImagePath.split("/").pop())
                : ""
        }
    }
}
