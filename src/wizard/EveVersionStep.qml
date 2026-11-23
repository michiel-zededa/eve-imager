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
    property var platformModel: []       // what the Platform list shows
    // One entry per line of platformModel: { label, platform, hardware }.
    // Most lines are a platform of the release. The OnLogic FR201 lines are
    // the generic arm64 image plus a change to its boot files, which is made
    // after writing (hardware: "fr201" | "fr201-nvme").
    property var platformChoices: []

    function _choice() {
        var i = platformCombo.currentIndex
        return (i >= 0 && i < root.platformChoices.length) ? root.platformChoices[i] : null
    }

    // The FR201 boot files are in EVE-OS 14.5 and later
    function _hasFr201Files(version) {
        var m = /^(\d+)\.(\d+)/.exec(version)
        if (!m) return false
        var major = parseInt(m[1]), minor = parseInt(m[2])
        return major > 14 || (major === 14 && minor >= 5)
    }

    function _setHardware(hw) {
        if (root.wizardContainer.eveConfig.hardware === hw) return
        var c = Object.assign({}, root.wizardContainer.eveConfig)
        c.hardware = hw
        root.wizardContainer.eveConfig = c
    }

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
        // Read the earlier choice first: filling the list below can already
        // move the selection, which writes it back
        var savedPlatform = root.wizardContainer.evePlatform
        var savedHardware = root.wizardContainer.eveConfig.hardware || ""
        var platforms = (v.length > 0 && a.length > 0 && h.length > 0)
                        ? releaseFetcher.platformsFor(v, a, h) : []
        var choices = []
        for (var i = 0; i < platforms.length; i++) {
            choices.push({ label: platforms[i], platform: platforms[i], hardware: "" })
            // EVE-OS supports the FR201 with KVM only. The boot files are
            // changed after writing, which only works for RAW images.
            if (platforms[i] === "generic" && a === "arm64" && h === "kvm" && root._hasFr201Files(v)
                    && !releaseFetcher.isIsoAsset(v, a, h, "generic")) {
                choices.push({ label: qsTr("OnLogic FR201"), platform: "generic", hardware: "fr201" })
                choices.push({ label: qsTr("OnLogic FR201 without eMMC"), platform: "generic", hardware: "fr201-nvme" })
            }
        }
        root.platformChoices = choices
        root.platformModel = choices.map(function(c) { return c.label })
        var idx = -1
        for (var j = 0; j < choices.length && idx < 0; j++)
            if (choices[j].platform === savedPlatform && choices[j].hardware === savedHardware)
                idx = j
        if (idx < 0)
            idx = platforms.indexOf(savedPlatform) >= 0
                  ? choices.map(function(c) { return c.label }).indexOf(savedPlatform) : -1
        platformCombo.currentIndex = (idx >= 0) ? idx : (choices.length > 0 ? 0 : -1)
        // Keep the wizard state up to date so the Writing step sees fresh values
        root._scheduleSync()
    }

    // The selection is written to the wizard once the lists have settled, not
    // at every step in between. While a list is being filled (the step is
    // opened again, or the releases are reloaded) the boxes pass through
    // "first entry" states; written back at once, those replaced the earlier
    // choice before it could be restored, so going back to this step lost the
    // version, architecture and platform that had been chosen.
    function _scheduleSync() {
        Qt.callLater(root._syncWizardDownloadState)
    }

    function _syncWizardDownloadState() {
        var v = versionCombo.currentIndex >= 0 ? releaseFetcher.versions[versionCombo.currentIndex] : ""
        var a = archCombo.currentIndex >= 0 ? root.archModel[archCombo.currentIndex] : ""
        var h = hvCombo.currentIndex >= 0 ? root.hvModel[hvCombo.currentIndex] : ""
        // The lists describe the release's preferred image. If its ISO had
        // been chosen for saving, that choice ends here: pick the destination again.
        if (root.wizardContainer.saveAsIso) {
            root.wizardContainer.saveAsIso = false
            root.wizardContainer.eveRawSelection = null
            root.wizardContainer.saveFilePath = ""
            root.wizardContainer.selectedStorageName = ""
            root.imageWriter.setDst("")
        }
        var choice = root._choice()
        var p = choice ? choice.platform : ""
        root._setHardware(choice ? choice.hardware : "")
        root.wizardContainer.eveVersion      = v
        root.wizardContainer.eveArch         = a
        root.wizardContainer.eveHypervisor   = h
        root.wizardContainer.evePlatform     = p
        var hasAll = v.length > 0 && a.length > 0 && h.length > 0 && p.length > 0
        root.wizardContainer.eveDownloadUrl  = hasAll ? releaseFetcher.downloadUrl(v, a, h, p) : ""
        root.wizardContainer.eveDownloadSize = hasAll ? releaseFetcher.downloadSize(v, a, h, p) : 0
        root.wizardContainer.eveIsCompressedImage = hasAll ? releaseFetcher.isCompressedAsset(v, a, h, p) : false
        root.wizardContainer.eveIsIsoImage   = hasAll ? releaseFetcher.isIsoAsset(v, a, h, p) : false
        // The release's installer ISO, offered for saving next to the raw image
        var hasOtherIso = hasAll && !root.wizardContainer.eveIsIsoImage
        root.wizardContainer.eveIsoUrl       = hasOtherIso ? releaseFetcher.isoDownloadUrl(v, a, h, p) : ""
        root.wizardContainer.eveIsoSize      = hasOtherIso ? releaseFetcher.isoDownloadSize(v, a, h, p) : 0
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
        root.wizardContainer.selectedOsName  = !hasAll ? ""
            : choice.hardware.length > 0
              ? qsTr("EVE-OS %1 · %2/%3/%4 for %5").arg(v).arg(a).arg(h).arg(p).arg(choice.label)
              : qsTr("EVE-OS %1 · %2/%3/%4").arg(v).arg(a).arg(h).arg(p)
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
                                    onCurrentIndexChanged: root._scheduleSync()
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
                            readonly property var choice: visible ? root._choice() : null
                            readonly property string p: choice ? choice.platform : ""

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
                                        var t = sz > 0 ? qsTr("%1 GB download").arg((sz / (1024*1024*1024)).toFixed(2))
                                                       : qsTr("Download")
                                        // The FR201 lines use the generic image: say what is done to it
                                        if (assetPreview.choice && assetPreview.choice.hardware === "fr201")
                                            t += " · " + qsTr("set up for the FR201")
                                        else if (assetPreview.choice && assetPreview.choice.hardware === "fr201-nvme")
                                            t += " · " + qsTr("set up for the FR201 without eMMC")
                                        return t
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
        // Releases loaded earlier are still listed when the step is opened
        // again: show the version that was chosen
        var saved = root.wizardContainer.eveVersion
        var idx = saved.length > 0 ? releaseFetcher.versions.indexOf(saved) : -1
        if (idx >= 0 && versionCombo.currentIndex !== idx)
            versionCombo.currentIndex = idx
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
            root._setHardware("")   // the hardware choice belongs to the Platform list
            root.wizardContainer.eveDownloadUrl  = ""
            root.wizardContainer.eveDownloadSize = 0
            root.wizardContainer.eveIsCompressedImage = false
            root.wizardContainer.eveImageSize = 0   // local files are sized by the writer itself
            root.wizardContainer.eveIsoUrl = ""
            root.wizardContainer.eveIsoSize = 0
            root.wizardContainer.eveIsIsoImage = root.wizardContainer.eveLocalImagePath.toLowerCase().endsWith(".iso")
            root.wizardContainer.selectedOsName  = root.wizardContainer.eveLocalImagePath.length > 0
                ? qsTr("Local image: %1").arg(root.wizardContainer.eveLocalImagePath.split("/").pop())
                : ""
        }
    }
}
