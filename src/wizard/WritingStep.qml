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
            return qsTr("Writing in progress — do not disconnect the storage device")
        } else if (root.isComplete) {
            return qsTr("Write complete")
        } else {
            return qsTr("Review your choices and write the image to the storage device")
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
    // For EVE, customizations are always shown when the eveConfig has any non-empty field
    readonly property bool anyCustomizationsApplied: false

    // Disable back while writing (but allow back after failure so user can retry)
    backButtonEnabled: !root.isWriting

    // Content
    content: [
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.cardPadding
        spacing: Style.spacingLarge

        // Top spacer to vertically center progress section when writing/complete/failed
        Item { Layout.fillHeight: true; visible: root.isWriting || root.isComplete || root.hasFailed }

        // Summary section (de-chromed)
        ColumnLayout {
            id: summaryLayout
            Layout.fillWidth: true
            Layout.maximumWidth: Style.sectionMaxWidth
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.spacingMedium
            visible: !root.isWriting && !root.isComplete && !root.hasFailed

            Text {
                id: summaryHeading
                text: qsTr("Summary")
                font.pointSize: Style.fontSizeHeading
                font.family: Style.fontFamilyBold
                font.bold: true
                color: Style.formLabelColor
                Layout.fillWidth: true
                Accessible.role: Accessible.Heading
                Accessible.name: text
                Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
                activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
            }

            GridLayout {
                id: summaryGrid
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Style.formColumnSpacing
                rowSpacing: Style.spacingSmall

                Text {
                    id: osLabel
                    text: qsTr("EVE OS image:")
                    font.pointSize: Style.fontSizeDescription
                    font.family: Style.fontFamily
                    color: Style.formLabelColor
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text + " " + (wizardContainer.selectedOsName || CommonStrings.noImageSelected)
                    Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                    focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
                    activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                }

                MarqueeText {
                    id: osValue
                    text: wizardContainer.selectedOsName || CommonStrings.noImageSelected
                    font.pointSize: Style.fontSizeDescription
                    font.family: Style.fontFamilyBold
                    font.bold: true
                    color: Style.formLabelColor
                    Layout.fillWidth: true
                    Accessible.ignored: true  // Read as part of the label
                }

                Text {
                    id: storageLabel
                    text: CommonStrings.storage
                    font.pointSize: Style.fontSizeDescription
                    font.family: Style.fontFamily
                    color: Style.formLabelColor
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text + ": " + (wizardContainer.selectedStorageName || CommonStrings.noStorageSelected)
                    Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                    focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
                    activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                }

                MarqueeText {
                    id: storageValue
                    text: wizardContainer.selectedStorageName || CommonStrings.noStorageSelected
                    font.pointSize: Style.fontSizeDescription
                    font.family: Style.fontFamilyBold
                    font.bold: true
                    color: Style.formLabelColor
                    Layout.fillWidth: true
                    Accessible.ignored: true  // Read as part of the label
                }
            }
        }

        // ISO notice — shown when writing an ISO (no config applied)
        Rectangle {
            id: isoNotice
            Layout.fillWidth: true
            Layout.maximumWidth: Style.sectionMaxWidth
            Layout.alignment: Qt.AlignHCenter
            color: "#fff3cd"
            border.color: "#ffc107"
            border.width: 1
            radius: Style.sectionBorderRadius
            height: isoNoticeText.implicitHeight + Style.spacingSmall * 2
            visible: !root.isWriting && !root.isComplete && !root.hasFailed
                     && root.wizardContainer.eveIsIsoImage

            Text {
                id: isoNoticeText
                anchors {
                    left: parent.left; right: parent.right
                    top: parent.top; margins: Style.spacingSmall
                }
                text: qsTr("⚠ ISO image — controller URL, network, and SSH settings cannot be "
                            + "pre-configured on ISO installers. The image will boot as a plain "
                            + "installer. Configure the device through the controller after installation.")
                font.family: Style.fontFamily
                font.pointSize: Style.fontSizeDescription
                color: "#856404"
                wrapMode: Text.WordWrap
            }
        }

        // Customization summary (what will be written) - de-chromed
        ColumnLayout {
            id: customLayout
            Layout.fillWidth: true
            Layout.maximumWidth: Style.sectionMaxWidth
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.spacingMedium
            visible: !root.isWriting && !root.isComplete && !root.hasFailed && root.anyCustomizationsApplied

            Text {
                id: customizationsHeading
                text: qsTr("Customisations to apply:")
                font.pointSize: Style.fontSizeHeading
                font.family: Style.fontFamilyBold
                font.bold: true
                color: Style.formLabelColor
                Layout.fillWidth: true
                Accessible.role: Accessible.Heading
                Accessible.name: text
                Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
                activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
            }

            ScrollView {
                id: customizationsScrollView
                Layout.fillWidth: true
                // Cap height so long lists become scrollable in default window size
                Layout.maximumHeight: Math.round(root.height * 0.4)
                clip: true
                activeFocusOnTab: true
                focusPolicy: Qt.TabFocus
                Accessible.role: Accessible.List
                Accessible.name: {
                    // Build a list of visible customizations to announce
                    var items = []
                    if (wizardContainer.hostnameConfigured) items.push(CommonStrings.hostnameConfigured)
                    if (wizardContainer.localeConfigured) items.push(CommonStrings.localeConfigured)
                    if (wizardContainer.userConfigured) items.push(CommonStrings.userAccountConfigured)
                    if (wizardContainer.wifiConfigured) items.push(CommonStrings.wifiConfigured)
                    if (wizardContainer.sshEnabled) items.push(CommonStrings.sshEnabled)
                    if (wizardContainer.piConnectEnabled) items.push(CommonStrings.piConnectEnabled)
                    if (wizardContainer.featUsbGadgetEnabled) items.push(CommonStrings.usbGadgetEnabled)
                    if (wizardContainer.ifI2cEnabled) items.push(CommonStrings.i2cEnabled)
                    if (wizardContainer.ifSpiEnabled) items.push(CommonStrings.spiEnabled)
                    if (wizardContainer.if1WireEnabled) items.push(CommonStrings.onewireEnabled)
                    if (wizardContainer.ifSerial !== "" && wizardContainer.ifSerial !== "Disabled") items.push(CommonStrings.serialConfigured)
                    
                    return items.length + " " + (items.length === 1 ? qsTr("customization") : qsTr("customizations")) + ": " + items.join(", ")
                }
                contentItem: Flickable {
                    id: customizationsFlickable
                    contentWidth: width
                    contentHeight: customizationsColumn.implicitHeight
                    interactive: contentHeight > height
                    clip: true
                    
                    Keys.onUpPressed: {
                        if (contentY > 0) {
                            contentY = Math.max(0, contentY - 20)
                        }
                    }
                    Keys.onDownPressed: {
                        var maxY = Math.max(0, contentHeight - height)
                        if (contentY < maxY) {
                            contentY = Math.min(maxY, contentY + 20)
                        }
                    }
                    Column {
                        id: customizationsColumn
                        width: parent.width
                        spacing: Style.spacingXSmall
                        // EVE OS imager: no RPi-specific customizations
                    }
                }
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    width: Style.scrollBarWidth
                }
            }
        }

        // Progress section (de-chromed)
        ColumnLayout {
            id: progressLayout
            Layout.fillWidth: true
            Layout.maximumWidth: Style.sectionMaxWidth
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.spacingMedium
            visible: root.isWriting || root.isComplete || root.hasFailed

            Text {
                id: progressText
                text: qsTr("Starting write process...")
                font.pointSize: Style.fontSizeHeading
                font.family: Style.fontFamilyBold
                font.bold: true
                color: Style.formLabelColor
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                Accessible.role: Accessible.StatusBar
                Accessible.name: text
                Accessible.focusable: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
                focusPolicy: (root.imageWriter && root.imageWriter.isScreenReaderActive()) ? Qt.TabFocus : Qt.NoFocus
                activeFocusOnTab: root.imageWriter ? root.imageWriter.isScreenReaderActive() : false
            }

            ProgressBar {
                id: progressBar
                Layout.fillWidth: true
                Layout.preferredHeight: Style.spacingLarge
                value: 0
                from: 0
                to: 100
                indeterminate: root.isIndeterminateProgress && !root.isVerifying && !root.isFinalising

                Material.accent: Style.progressBarVerifyForegroundColor
                Material.background: Style.progressBarBackgroundColor
                visible: root.isWriting
                Accessible.role: Accessible.ProgressBar
                Accessible.name: qsTr("Write progress")
                Accessible.description: progressText.text
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
                font.pointSize: Style.fontSizeSmall
                font.family: Style.fontFamily
                color: Style.formLabelDisabledColor
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                visible: root.isWriting && root.bottleneckStatus !== ""
            }
            
            // Operation warning (e.g., sync fallback due to slow device)
            Text {
                id: operationWarningText
                text: "⚠ " + root.operationWarning
                font.pointSize: Style.fontSizeSmall
                font.family: Style.fontFamily
                color: "#FFA500"  // Orange/amber for warning
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: root.isWriting && root.operationWarning !== ""
            }

            // Error box — shown when write fails so the message isn't lost
            Rectangle {
                id: errorBox
                Layout.fillWidth: true
                color: "#fdecea"
                border.color: "#e57373"
                border.width: 1
                radius: Style.sectionBorderRadius
                height: errorColumn.implicitHeight + Style.spacingMedium * 2
                visible: root.hasFailed && root.errorMessage.length > 0

                ColumnLayout {
                    id: errorColumn
                    anchors {
                        left: parent.left; right: parent.right
                        top: parent.top
                        margins: Style.spacingMedium
                    }
                    spacing: Style.spacingSmall

                    Text {
                        text: qsTr("Write failed")
                        font.pointSize: Style.fontSizeFormLabel
                        font.family: Style.fontFamilyBold
                        font.bold: true
                        color: "#c62828"
                        Layout.fillWidth: true
                    }
                    Text {
                        text: root.errorMessage
                        font.pointSize: Style.fontSizeDescription
                        font.family: Style.fontFamily
                        color: Style.formLabelColor
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        textFormat: Text.StyledText
                    }
                    Text {
                        text: qsTr("Press ← Back to return and try again.")
                        font.pointSize: Style.fontSizeDescription
                        font.family: Style.fontFamily
                        color: Style.textDescriptionColor
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        // Bottom spacer to vertically center progress section when writing/complete/failed
        Item { Layout.fillHeight: true; visible: root.isWriting || root.isComplete || root.hasFailed }
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
                progressBar.value = 100
                progressText.text = qsTr("Finalising…")
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
        progressText.text = qsTr("Finalising...")
        progressBar.value = 100
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
            font.bold: true
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

        // Bottom spacer to balance the dialog's internal top padding
        Item { Layout.preferredHeight: Style.cardPadding }
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
            imageWriter.startWrite()
        }
    }

    function onDownloadProgress(now, total) {
        // Download progress is tracked for performance stats but not shown in UI
        // (the write progress is more accurate as it reflects actual data written to disk)
    }

    function onWriteProgress(now, total) {
        if (root.isWriting) {
            if (root.isIndeterminateProgress) {
                // Show indeterminate progress with bytes written (in human-readable format)
                var bytesWrittenMB = Math.round(now / (1024 * 1024))
                progressText.text = qsTr("Writing... %1 MB written").arg(bytesWrittenMB)
            } else {
                var progress = total > 0 ? (now / total) * 100 : 0
                progressBar.value = progress
                progressText.text = qsTr("Writing... %1%").arg(Math.round(progress))
            }
        }
    }

    function onVerifyProgress(now, total) {
        if (root.isWriting) {
            root.operationWarning = ""  // Clear write warnings during verification
            var progress = total > 0 ? (now / total) * 100 : 0
            progressBar.value = progress
            progressText.text = qsTr("Verifying... %1%").arg(Math.round(progress))
        }
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
            if (root.isWriting) {
                if (root.isIndeterminateProgress) {
                    var bytesWrittenMB = Math.round(now / (1024 * 1024))
                    progressText.text = qsTr("Writing… %1 MB written").arg(bytesWrittenMB)
                } else {
                    var progress = total > 0 ? (now / total) * 100 : 0
                    progressBar.value = progress
                    progressText.text = qsTr("Writing… %1%").arg(Math.round(progress))
                }
            }
        }

        function onVerifyProgress(now, total) {
            if (root.isWriting) {
                root.operationWarning = ""
                var progress = total > 0 ? (now / total) * 100 : 0
                progressBar.value = progress
                progressText.text = qsTr("Verifying… %1%").arg(Math.round(progress))
            }
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

        function onFinalizing() {
            if (root.isWriting) {
                progressText.text = qsTr("Finalising…")
                progressBar.value = 100
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
    onAnyCustomizationsAppliedChanged: rebuildFocusOrder()
    
    Component.onCompleted: {
        // Configure image source and EVE config whenever this step is shown
        var cfg = root.wizardContainer
        if (cfg.useLocalImage && cfg.eveLocalImagePath.length > 0) {
            root.imageWriter.setSrc("file://" + cfg.eveLocalImagePath)
        } else if (cfg.eveDownloadUrl.length > 0) {
            // Use the URL and size resolved by EveVersionStep (Phase 2 live releases)
            root.imageWriter.setSrc(cfg.eveDownloadUrl,
                                    cfg.eveDownloadSize, cfg.eveDownloadSize,
                                    "", false, "EVE OS", cfg.selectedOsName)
        } else if (cfg.eveVersion.length > 0) {
            // Fallback: construct URL from version/arch/hv/platform
            var assetName = cfg.eveArch + "." + cfg.eveHypervisor + "." + cfg.evePlatform + ".installer.raw"
            var dlUrl = "https://github.com/lf-edge/eve/releases/download/" + cfg.eveVersion + "/" + assetName
            root.imageWriter.setSrc(dlUrl, 0, 0, "", false, "EVE OS", cfg.selectedOsName)
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
                }
            }
            return items
        }, 0)
        
        // Register customizations section as second focus group
        registerFocusGroup("customizations", function() {
            var items = []
            if (customLayout.visible) {
                // Only include heading when screen reader is active; always include scroll view
                if (root.imageWriter && root.imageWriter.isScreenReaderActive()) {
                    items.push(customizationsHeading)
                }
                items.push(customizationsScrollView)
            }
            return items
        }, 1)
        
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
