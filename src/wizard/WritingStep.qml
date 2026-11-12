/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2020 Raspberry Pi Ltd
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../qmlcomponents"

import RpiImager
import ImageOptions

WizardStepBase {
    id: root
    objectName: "writingStep"

    required property ImageWriter imageWriter
    required property var wizardContainer

    title: qsTr("Write image")
    subtitle: {
        if (root.isWriting) {
            return qsTr("Writing in progress. Do not disconnect the storage device.")
        } else if (root.isComplete) {
            return qsTr("Write complete")
        } else {
            return qsTr("Review your choices, then write the image to the storage device.")
        }
    }
    nextButtonText: {
        if (root.isWriting) {
            // Show specific cancel text based on write state
            if (imageWriter.writeState === ImageWriter.Verifying) {
                return qsTr("Skip verification")
            } else {
                return qsTr("Cancel write")
            }
        } else if (root.isComplete) {
            return CommonStrings.continueText
        } else {
            return qsTr("Write")
        }
    }
    nextButtonAccessibleDescription: {
        if (root.isWriting) {
            if (imageWriter.writeState === ImageWriter.Verifying) {
                return qsTr("Skip verification and finish the write process")
            } else {
                return qsTr("Cancel the write operation and return to the summary")
            }
        } else if (root.isComplete) {
            return qsTr("Continue to the completion screen")
        } else {
            return qsTr("Begin writing the image to the storage device. All existing data will be erased.")
        }
    }
    backButtonAccessibleDescription: qsTr("Return to previous customization step")
    // _srcReady is set true in Component.onCompleted after setSrc() — this makes the
    // nextButtonEnabled binding re-evaluate once the image source is configured.
    property bool _srcReady: false
    nextButtonEnabled: root.isWriting || root.isComplete || (root.hasFailed ? false : (!beginWriteDelay.running && root._srcReady && imageWriter.readyToWrite()))
    showBackButton: true

    readonly property bool isWriting: {
        var s = imageWriter.writeState
        return s === ImageWriter.Preparing || s === ImageWriter.Writing ||
               s === ImageWriter.Verifying || s === ImageWriter.Finalizing ||
               s === ImageWriter.Cancelling
    }
    readonly property bool isVerifying: imageWriter.writeState === ImageWriter.Verifying
    readonly property bool isCancelling: imageWriter.writeState === ImageWriter.Cancelling
    readonly property bool isFinalising: imageWriter.writeState === ImageWriter.Finalizing
    readonly property bool isComplete: imageWriter.writeState === ImageWriter.Succeeded
    readonly property bool hasFailed: imageWriter.writeState === ImageWriter.Failed ||
                                      imageWriter.writeState === ImageWriter.Cancelled
    property string errorMessage: ""
    property string bottleneckStatus: ""
    property int writeThroughputKBps: 0
    property string operationWarning: ""  // Non-fatal warning message (e.g., sync fallback)
    property bool isIndeterminateProgress: false  // True when we can't determine accurate progress (e.g., gz files >4GB)

    // Disable back while writing (but allow back after failure so user can retry)
    backButtonEnabled: !root.isWriting

    // The red outline is for stopping a write, not for skipping verification
    nextButtonDanger: root.isWriting && !root.isVerifying

    // Progress shown in the card: percentage (-1 = not known) and a line of detail
    property real progressPercent: -1
    readonly property string phaseLabel: root.hasFailed ? qsTr("Failed")
                                       : root.isCancelling ? qsTr("Cancelling")
                                       : root.isFinalising ? qsTr("Finishing")
                                       : root.isVerifying ? qsTr("Verifying")
                                       : imageWriter.writeState === ImageWriter.Writing ? qsTr("Writing")
                                       : qsTr("Preparing")

    function showWriteProgress(now, total) {
        if (!root.isWriting)
            return
        if (root.isIndeterminateProgress || total <= 0) {
            root.progressPercent = -1
            progressText.text = qsTr("%1 written to the drive").arg(imageWriter.formatSize(now))
        } else {
            var progress = (now / total) * 100
            progressBar.value = progress
            root.progressPercent = progress
            progressText.text = qsTr("%1 of %2 written to the drive").arg(imageWriter.formatSize(now)).arg(imageWriter.formatSize(total))
        }
    }

    function showVerifyProgress(now, total) {
        if (!root.isWriting)
            return
        root.operationWarning = ""  // Clear write warnings during verification
        var progress = total > 0 ? (now / total) * 100 : 0
        progressBar.value = progress
        root.progressPercent = progress
        progressText.text = qsTr("%1 of %2 verified").arg(imageWriter.formatSize(now)).arg(imageWriter.formatSize(total))
    }

    function showFinalizing() {
        progressText.text = qsTr("Finishing up…")
        progressBar.value = 100
        root.progressPercent = 100
    }

    component CardHeading: Text {
        font.family: Style.fontFamily
        font.pointSize: Style.fontSizeCaption
        font.weight: Style.fontWeightSemiBold
        font.letterSpacing: 1.1
        font.capitalization: Font.AllUppercase
        color: Style.muted
    }

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

    // Content
    content: [
    ColumnLayout {
        anchors.fill: parent
        spacing: Style.spacingSmallPlus

        // Summary: stays visible while writing, so it is always clear what goes where
        ImCard {
            id: summaryLayout
            Layout.fillWidth: true
            padding: 0
            spacing: 0

            CardHeading {
                id: summaryHeading
                text: qsTr("Summary")
                Layout.leftMargin: Style.cardPadding
                Layout.topMargin: Style.spacingSmallPlus
                Layout.bottomMargin: Style.spacingSmallPlus
                Accessible.role: Accessible.Heading
                Accessible.name: text
                Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
                activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.border }

            GridLayout {
                id: summaryGrid
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
                    Accessible.name: text + ": " + (wizardContainer.selectedOsName || CommonStrings.noImageSelected)
                }

                MarqueeText {
                    id: osValue
                    text: wizardContainer.selectedOsName || CommonStrings.noImageSelected
                    font.pointSize: Style.fontSizeFormLabel
                    font.family: Style.fontFamily
                    color: Style.text
                    Layout.fillWidth: true
                    Accessible.ignored: true  // Read as part of the label
                }

                SummaryLabel {
                    id: storageLabel
                    text: qsTr("Storage")
                    Accessible.name: text + ": " + (wizardContainer.selectedStorageName || CommonStrings.noStorageSelected)
                }

                MarqueeText {
                    id: storageValue
                    text: wizardContainer.selectedStorageName || CommonStrings.noStorageSelected
                    font.pointSize: Style.fontSizeFormLabel
                    font.family: Style.fontFamily
                    color: Style.text
                    Layout.fillWidth: true
                    Accessible.ignored: true  // Read as part of the label
                }

                SummaryLabel {
                    id: configLabel
                    text: qsTr("Configuration")
                    Accessible.name: text + ": " + configValue.text
                }

                Text {
                    id: configValue
                    text: root.wizardContainer.eveConfigSummary()
                    font.pointSize: Style.fontSizeFormLabel
                    font.family: Style.fontFamily
                    color: Style.text
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Accessible.ignored: true  // Read as part of the label
                }
            }
        }

        // ISO notice — shown when writing an ISO (no config applied)
        ImBanner {
            id: isoNotice
            Layout.fillWidth: true
            kind: "warn"
            visible: !root.isWriting && !root.isComplete && !root.hasFailed
                     && root.wizardContainer.eveIsIsoImage
            text: qsTr("ISO image: controller URL, network, and SSH settings cannot be "
                       + "pre-configured on ISO installers. The image will boot as a plain "
                       + "installer. Configure the device through the controller after installation.")
        }

        // What happens next, before the write starts
        ImBanner {
            Layout.fillWidth: true
            kind: "neutral"
            visible: !root.isWriting && !root.isComplete && !root.hasFailed
            text: qsTr("Writing erases everything on the storage device.")
        }

        // Progress card
        ImCard {
            id: progressLayout
            Layout.fillWidth: true
            spacing: Style.spacingSmallPlus
            visible: root.isWriting || root.isComplete

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.spacingMedium

                ColumnLayout {
                    spacing: Style.spacingXXSmall

                    CardHeading { text: root.phaseLabel }

                    Text {
                        id: percentText
                        // No number while the size is unknown or nothing is being counted
                        visible: root.progressPercent >= 0 && !progressBar.indeterminate
                        text: qsTr("%1%").arg(Math.round(root.progressPercent))
                        font.family: Style.fontFamily
                        font.pointSize: Math.round(Style.fontSizeTitle * 1.35)
                        font.weight: Style.fontWeightSemiBold
                        font.letterSpacing: -0.6
                        color: Style.text
                        Accessible.ignored: true
                    }
                }

                Text {
                    id: progressText
                    text: qsTr("Starting write process...")
                    font.pointSize: Style.fontSizeFormLabel
                    font.family: Style.fontFamily
                    font.weight: Style.fontWeightMedium
                    color: Style.text
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: Style.spacingXSmall
                    horizontalAlignment: Text.AlignRight
                    wrapMode: Text.WordWrap
                    Accessible.role: Accessible.StatusBar
                    Accessible.name: root.phaseLabel + (percentText.visible ? " " + percentText.text : "") + ". " + text
                    Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                    focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
                    activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                }
            }

            ImProgressBar {
                id: progressBar
                Layout.fillWidth: true
                value: 0
                from: 0
                to: 100
                indeterminate: (root.isIndeterminateProgress && !root.isVerifying && !root.isFinalising)
                               || imageWriter.writeState === ImageWriter.Preparing
                               || root.isCancelling
                fillColor: root.isVerifying ? Style.progressBarVerifyForegroundColor : Style.progressBarWritingForegroundColor
                visible: root.isWriting
                Accessible.role: Accessible.ProgressBar
                Accessible.name: qsTr("Write progress")
                Accessible.description: progressText.text
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.spacingTiny
                visible: root.isWriting

                // The stages of a write; the current one is highlighted
                ImPill {
                    text: qsTr("1 Write")
                    readonly property bool done: root.isVerifying || root.isFinalising
                    kind: done ? "ok" : (imageWriter.writeState === ImageWriter.Writing || imageWriter.writeState === ImageWriter.Preparing) ? "neutral" : "plain"
                    iconName: done ? "check" : ""
                }
                ImPill {
                    text: qsTr("2 Verify")
                    readonly property bool done: root.isFinalising
                    kind: done ? "ok" : root.isVerifying ? "neutral" : "plain"
                    iconName: done ? "check" : ""
                }
                ImPill {
                    text: qsTr("3 Finish")
                    kind: root.isFinalising ? "neutral" : "plain"
                }

                // Bottleneck status indicator - shows what's limiting progress
                Text {
                    id: bottleneckText
                    text: {
                        if (root.bottleneckStatus !== "") {
                            if (root.writeThroughputKBps > 0) {
                                return root.bottleneckStatus + " (" + Math.round(root.writeThroughputKBps / 1024) + " MB/s)"
                            }
                            return root.bottleneckStatus
                        }
                        return ""
                    }
                    font.pointSize: Style.fontSizeDescription
                    font.family: Style.fontFamily
                    color: Style.muted
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideLeft
                    visible: root.bottleneckStatus !== ""
                }
            }

            // Operation warning (e.g., sync fallback due to slow device)
            ImBanner {
                id: operationWarningText
                Layout.fillWidth: true
                kind: "warn"
                text: root.operationWarning
                visible: root.isWriting && root.operationWarning !== ""
            }
        }

        // Error box — shown when write fails so the message isn't lost
        Rectangle {
            id: errorBox
            Layout.fillWidth: true
            color: Style.errBg
            border.color: Style.errBorder
            border.width: 1
            radius: Style.sectionBorderRadius
            implicitHeight: errorColumn.implicitHeight + Style.cardPadding * 2
            visible: root.hasFailed && root.errorMessage.length > 0

            ColumnLayout {
                id: errorColumn
                anchors {
                    left: parent.left; right: parent.right
                    top: parent.top
                    margins: Style.cardPadding
                }
                spacing: Style.spacingTiny

                RowLayout {
                    spacing: Style.spacingTiny
                    ImIcon { name: "x-circle"; color: Style.err; size: Style.scaled(18) }
                    Text {
                        text: qsTr("Write failed")
                        font.pointSize: Style.fontSizeFormLabel
                        font.family: Style.fontFamily
                        font.weight: Style.fontWeightSemiBold
                        color: Style.err
                        Layout.fillWidth: true
                    }
                }
                Text {
                    text: root.errorMessage
                    font.pointSize: Style.fontSizeDescription
                    font.family: Style.fontFamily
                    color: Style.text
                    linkColor: Style.accentText
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    textFormat: Text.StyledText
                }
                Text {
                    text: qsTr("Press Back to return and try again.")
                    font.pointSize: Style.fontSizeDescription
                    font.family: Style.fontFamily
                    color: Style.muted
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
    ]

    // Handle next button clicks based on current state
    onNextClicked: {
        if (root.isWriting) {
            // If we're in verification phase, skip verification and let write complete successfully
            if (imageWriter.writeState === ImageWriter.Verifying) {
                imageWriter.skipCurrentVerification()
            } else {
                // Cancel the actual write operation
                progressText.text = qsTr("Stopping the write…")
                imageWriter.cancelWrite()
            }
        } else if (!root.isComplete) {
            // If warnings are disabled, skip the confirmation dialog
            if (wizardContainer.disableWarnings) {
                beginWriteDelay.start()
            } else {
                // Open confirmation dialog before starting
                confirmDialog.open()
            }
        } else {
            // Writing is complete, advance to next step
            wizardContainer.nextStep()
        }
    }

    function onFinalizing() {
        root.showFinalizing()
    }

    // Confirmation dialog
    BaseDialog {
        id: confirmDialog
        imageWriter: root.imageWriter
        parent: root.Window.window ? root.Window.window.overlayRootItem : undefined
        anchors.centerIn: parent

        // Override height with maximum constraint to prevent excessive height, but allow natural sizing
        height: Math.min(400, contentLayout ? (contentLayout.implicitHeight + Style.cardPadding * 2) : 200)

        property bool allowAccept: false
        property int countdown: 2

        // Custom escape handling
        function escapePressed() {
            confirmDialog.close()
        }

        // Register focus groups when component is ready
        Component.onCompleted: {
            registerFocusGroup("warning", function(){ 
                // Only include warning texts when screen reader is active (otherwise they're not focusable)
                if (confirmDialog.imageWriter && confirmDialog.imageWriter.isScreenReaderActive()) {
                    return [warningText, permanentText]
                }
                return []
            }, 0)
            registerFocusGroup("buttons", function(){ 
                // Only include buttons when they're visible (after allowAccept becomes true)
                return confirmDialog.allowAccept ? [cancelButton, acceptBtn] : []
            }, 1)
        }

        onOpened: {
            // If a screen reader is active, bypass the timer - screen reader users
            // need time to hear the content, not wait for a visual countdown
            if (confirmDialog.imageWriter && confirmDialog.imageWriter.isScreenReaderActive()) {
                allowAccept = true
                countdown = 0
                rebuildFocusOrder()
            } else {
                allowAccept = false
                countdown = 2
                confirmDelay.start()
            }
        }
        onClosed: {
            confirmDelay.stop()
            allowAccept = false
            countdown = 2
        }

        // Dialog content - now using BaseDialog's contentLayout
        Text {
            id: warningText
            text: qsTr("You are about to ERASE all data on: %1").arg(wizardContainer.selectedStorageName || qsTr("the storage device"))
            font.pointSize: Style.fontSizeHeading
            font.family: Style.fontFamilyBold
            font.weight: Style.fontWeightSemiBold
            color: Style.formLabelErrorColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Accessible.role: Accessible.Heading
            Accessible.name: text
            Accessible.ignored: false
            Accessible.focusable: confirmDialog.imageWriter ? confirmDialog.imageWriter.isScreenReaderActive() : false
            focusPolicy: (confirmDialog.imageWriter && confirmDialog.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
            activeFocusOnTab: confirmDialog.imageWriter ? confirmDialog.imageWriter.isScreenReaderActive() : false
        }

        Text {
            id: permanentText
            text: qsTr("This action is PERMANENT and CANNOT be undone.")
            font.pointSize: Style.fontSizeFormLabel
            font.family: Style.fontFamilyBold
            color: Style.formLabelColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Accessible.role: Accessible.StaticText
            Accessible.name: text
            Accessible.ignored: false
            Accessible.focusable: confirmDialog.imageWriter ? confirmDialog.imageWriter.isScreenReaderActive() : false
            focusPolicy: (confirmDialog.imageWriter && confirmDialog.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
            activeFocusOnTab: confirmDialog.imageWriter ? confirmDialog.imageWriter.isScreenReaderActive() : false
        }

        Text {
            id: waitText
            text: qsTr("Please wait... %1").arg(confirmDialog.countdown)
            font.pointSize: Style.fontSizeFormLabel
            font.family: Style.fontFamily
            color: Style.textMetadataColor
            horizontalAlignment: Text.AlignRight
            Layout.fillWidth: true
            Layout.topMargin: Style.spacingSmall
            visible: !confirmDialog.allowAccept
        }

        RowLayout {
            id: confirmButtonRow
            Layout.fillWidth: true
            Layout.topMargin: Style.spacingSmall
            spacing: Style.spacingMedium
            visible: confirmDialog.allowAccept
            Item { Layout.fillWidth: true }

            ImButton {
                id: cancelButton
                text: CommonStrings.cancel
                accessibleDescription: qsTr("Cancel and return to the write summary without erasing the storage device")
                activeFocusOnTab: true
                onClicked: confirmDialog.close()
            }

            ImButtonRed {
                id: acceptBtn
                text: confirmDialog.allowAccept ? qsTr("I understand, erase and write") : qsTr("Please wait...")
                accessibleDescription: qsTr("Confirm erasure and begin writing the image to the storage device")
                enabled: confirmDialog.allowAccept
                activeFocusOnTab: true
                onClicked: {
                    confirmDialog.close()
                    beginWriteDelay.start()
                }
            }
        }
    }

    // Delay accept for 2 seconds - moved outside dialog content
    Timer {
        id: confirmDelay
        interval: 1000
        running: false
        repeat: true
        onTriggered: {
            confirmDialog.countdown--
            if (confirmDialog.countdown <= 0) {
                confirmDelay.stop()
                confirmDialog.allowAccept = true
                // Rebuild focus order now that buttons are visible
                confirmDialog.rebuildFocusOrder()
            }
        }
    }

    // Defer starting the write slightly until after the dialog has fully closed,
    // to avoid OS authentication prompts being cancelled by focus changes.
    Timer {
        id: beginWriteDelay
        interval: 300
        running: false
        repeat: false
        onTriggered: {
            // Ensure our window regains focus before elevating privileges
            root.forceActiveFocus()
            root.bottleneckStatus = ""
            root.writeThroughputKBps = 0
            root.operationWarning = ""
            root.errorMessage = ""
            // Check if extract size is known upfront (e.g., gz files can't reliably store sizes >4GB)
            root.isIndeterminateProgress = !imageWriter.isExtractSizeKnown()
            progressText.text = qsTr("Starting write process...")
            progressBar.value = 0
            root.progressPercent = -1
            imageWriter.startWrite()
        }
    }

    function onDownloadProgress(now, total) {
        // Download progress is tracked for performance stats but not shown in UI
        // (the write progress is more accurate as it reflects actual data written to disk)
    }

    function onWriteProgress(now, total) {
        root.showWriteProgress(now, total)
    }

    function onVerifyProgress(now, total) {
        root.showVerifyProgress(now, total)
    }

    function onPreparationStatusUpdate(msg) {
        if (root.isWriting) {
            progressText.text = msg
        }
    }

    // Update isWriting state when write completes
    Connections {
        target: imageWriter

        function onWriteProgress(now, total) {
            root.showWriteProgress(now, total)
        }

        function onVerifyProgress(now, total) {
            root.showVerifyProgress(now, total)
        }

        function onPreparationStatusUpdate(msg) {
            if (root.isWriting) {
                progressText.text = msg
            }
        }

        function onSuccess() {
            progressText.text = qsTr("Write completed successfully!")
            wizardContainer.nextStep()
        }

        function onError(msg) {
            root.errorMessage = msg
            progressText.text = qsTr("Write failed")
        }

        // The user cancelled the write: go back to the summary, ready to
        // write again (this is what the Cancel button's description promises).
        // Without this the step stayed on an empty progress view with the
        // Write button disabled.
        function onCancelled() {
            root.imageWriter.resetWriteState()
        }

        function onFinalizing() {
            if (root.isWriting) {
                root.showFinalizing()
            }
        }

        function onBottleneckStatusChanged(status, throughputKBps) {
            root.bottleneckStatus = status
            root.writeThroughputKBps = throughputKBps
        }

        function onOperationWarning(message) {
            root.operationWarning = message
        }
    }
    
    // Focus management - rebuild when visibility changes between phases
    onIsWritingChanged: rebuildFocusOrder()
    onIsCompleteChanged: rebuildFocusOrder()
    
    Component.onCompleted: {
        // Configure image source and EVE config whenever this step is shown
        var cfg = root.wizardContainer
        if (cfg.useLocalImage && cfg.eveLocalImagePath.length > 0) {
            root.imageWriter.setSrc("file://" + cfg.eveLocalImagePath)
        } else if (cfg.eveDownloadUrl.length > 0) {
            // Use the URL and size resolved by EveVersionStep (Phase 2 live releases).
            // The GitHub asset size is the *download* size. It only equals the size of
            // the image written to the device for uncompressed assets (.raw / .iso).
            // For compressed assets (.raw.zst, legacy .img) the extracted size is
            // what EveVersionStep read from the file's header (eveImageSize), or 0
            // ("unknown") if that was not possible — never the compressed size, which
            // the writer would reject as "not a multiple of 512 bytes". With a known
            // size the writer refuses drives that are too small before touching them
            // and can show a percentage.
            var extractSize = cfg.eveIsCompressedImage ? cfg.eveImageSize : cfg.eveDownloadSize
            root.imageWriter.setSrc(cfg.eveDownloadUrl,
                                    cfg.eveDownloadSize, extractSize,
                                    "", false, "EVE-OS", cfg.selectedOsName)
        } else if (cfg.eveVersion.length > 0) {
            // Fallback: construct URL from version/arch/hv/platform
            var assetName = cfg.eveArch + "." + cfg.eveHypervisor + "." + cfg.evePlatform + ".installer.raw"
            var dlUrl = "https://github.com/lf-edge/eve/releases/download/" + cfg.eveVersion + "/" + assetName
            root.imageWriter.setSrc(dlUrl, 0, 0, "", false, "EVE-OS", cfg.selectedOsName)
        }
        // Don't pass EVE config for ISO images — ISOs have no CONFIG partition
        if (!cfg.eveIsIsoImage) {
            root.imageWriter.setEveConfig(cfg.eveConfig)
        } else {
            root.imageWriter.setEveConfig({})
        }
        root._srcReady = true    // unblock the Write button binding

        // Register summary section as first focus group
        registerFocusGroup("summary", function() {
            var items = []
            if (summaryLayout.visible) {
                // Only include text labels when screen reader is active
                if (root.imageWriter && root.imageWriter.isScreenReaderActive()) {
                    items.push(summaryHeading)
                    items.push(osLabel)
                    items.push(storageLabel)
                    items.push(configLabel)
                }
            }
            return items
        }, 0)
        
        // Register progress section (when writing/complete)
        registerFocusGroup("progress", function() {
            var items = []
            if (progressLayout.visible) {
                // Only include progress text when screen reader is active
                if (root.imageWriter && root.imageWriter.isScreenReaderActive()) {
                    items.push(progressText)
                }
                // Always include progress bar when visible (during writing)
                if (progressBar.visible) {
                    items.push(progressBar)
                }
            }
            return items
        }, 0)
        
        // Let WizardStepBase handle initial focus (title first)
        // Ensure focus order is built when component completes
        Qt.callLater(function() {
            rebuildFocusOrder()
        })
    }
}
