/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 ZEDEDA, Inc.
 *
 * EVE OS Imager — main wizard container.
 * Five sequential steps:
 *   0  EveVersionStep      — choose EVE version / local image
 *   1  StorageSelectionStep — pick target drive
 *   2  EveCustomizationStep — controller URL, network, certs
 *   3  WritingStep          — write + verify progress
 *   4  DoneStep             — completion screen
 */
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../qmlcomponents"

import RpiImager

Item {
    id: root

    required property ImageWriter imageWriter
    property int sidebarWidthValue: Style.sidebarWidth
    property var optionsPopup: null
    property var overlayRootRef: null
    property string networkInfoText: ""

    // ── Step index constants ──────────────────────────────────────────────
    readonly property int stepEveVersion:        0
    readonly property int stepStorageSelection:  1
    readonly property int stepEveCustomization:  2
    readonly property int stepWriting:           3
    readonly property int stepDone:              4
    readonly property int totalSteps:            5

    // Current step — starts at 0, driven by nextStep() / previousStep()
    property int currentStep: 0

    // Sidebar label for each step
    readonly property var stepNames: [
        qsTr("Version"),
        qsTr("Storage"),
        qsTr("Configuration (optional)"),
        qsTr("Write"),
        qsTr("Done")
    ]

    // ── Write state (derived from C++ state machine) ─────────────────────
    readonly property bool isWriting: {
        var s = imageWriter.writeState
        return s === ImageWriter.Preparing || s === ImageWriter.Writing ||
               s === ImageWriter.Verifying || s === ImageWriter.Finalizing ||
               s === ImageWriter.Cancelling
    }

    // ── Step unlock tracking ──────────────────────────────────────────────
    // Bit N is set when step N becomes navigable (user has passed through it).
    property int permissibleStepsBitmap: 1   // step 0 always open

    function markStepPermissible(stepIndex) {
        permissibleStepsBitmap |= (1 << stepIndex)
    }
    function isStepPermissible(stepIndex) {
        return (permissibleStepsBitmap & (1 << stepIndex)) !== 0
    }
    function invalidateStepsFrom(fromStepIndex) {
        var mask = (1 << fromStepIndex) - 1
        permissibleStepsBitmap &= mask
    }

    // ── Selections (displayed in WritingStep summary) ─────────────────────
    property string selectedOsName: ""        // e.g. "EVE OS 12.5.0 amd64/kvm/generic"
    property string selectedStorageName: ""
    property string selectedDeviceName: selectedStorageName  // alias for DoneStep

    // ── Completion snapshot (used by DoneStep — all false for EVE imager) ──
    property var completionSnapshot: ({
        customizationSupported: false,
        hostnameConfigured: false,
        localeConfigured: false,
        userConfigured: false,
        wifiConfigured: false,
        sshEnabled: false,
        piConnectEnabled: false,
        ifI2cEnabled: false,
        ifSpiEnabled: false,
        if1WireEnabled: false,
        ifSerial: "",
        featUsbGadgetEnabled: false
    })

    // ── EVE version / image selection ─────────────────────────────────────
    property string eveVersion: ""            // e.g. "12.5.0"
    property string eveArch: "amd64"          // amd64 | arm64 | riscv64
    property string eveHypervisor: "kvm"      // kvm | xen
    property string evePlatform: "generic"    // generic | nvidia-jp5 | …
    property string eveLocalImagePath: ""     // set when user picks a local .raw file
    property bool   useLocalImage: false
    property string eveDownloadUrl: ""        // resolved by EveVersionStep.syncState()
    property int    eveDownloadSize: 0        // file size in bytes (for progress bar)
    property bool   eveIsIsoImage: false      // true = ISO asset (no config customization)

    // ── EVE device configuration ──────────────────────────────────────────
    property var eveConfig: ({
        controllerUrl:      "",
        networkMode:        "dhcp",   // "dhcp" | "static"
        staticIp:           "",
        gateway:            "",
        dns:                "",
        proxyUrl:           "",
        wifiSsid:           "",   // WiFi SSID
        wifiPassword:       "",   // WiFi pre-shared key
        rootCertPath:       "",   // root-certificate.pem (controller CA)
        authorizedKeys:     "",   // authorized_keys (SSH public key text)
        installDisk:        "",   // eve_install_disk grub param
        persistDisk:        "",   // eve_persist_disk grub param
        rebootAfterInstall: false // eve_reboot_after_install grub param
    })
    property bool eveConfigured: false

    // "Write another" mode — skip straight to WritingStep after storage re-selection
    property bool writeAnotherMode: false

    // Ephemeral per-run preference: suppress confirmation dialogs for this session
    property bool disableWarnings: false

    signal wizardCompleted()

    // ── Focus anchor for global Tab key handling ──────────────────────────
    Item {
        id: focusAnchor
        focus: true
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Tab) {
                var currentStepItem = wizardStack.currentItem
                if (currentStepItem && typeof currentStepItem.getNextFocusableElement === 'function') {
                    if (event.modifiers & Qt.ShiftModifier) {
                        var prev = currentStepItem.getPreviousFocusableElement(null)
                        if (prev) prev.forceActiveFocus()
                    } else {
                        var next = currentStepItem.getNextFocusableElement(null)
                        if (next) next.forceActiveFocus()
                    }
                    event.accepted = true
                }
            }
        }
    }

    Component.onCompleted: {
        if (imageWriter) {
            // Restore persisted sidebar width
            var savedWidth = imageWriter.getStringSetting("sidebarWidth")
            if (savedWidth) {
                sidebarWidthValue = clampSidebarWidth(parseInt(savedWidth))
            }
        }
    }

    // ── Sidebar helpers ───────────────────────────────────────────────────
    function clampSidebarWidth(width) {
        return Math.max(Style.sidebarMinWidth, Math.min(Style.sidebarMaxWidth, width))
    }
    function saveSidebarWidth(width) {
        if (imageWriter) imageWriter.setSetting("sidebarWidth", width.toString())
    }

    // Sidebar index === step index (1:1 mapping for EVE's flat 5-step flow)
    function getSidebarIndex(wizardStep) { return wizardStep }
    function getWizardStepFromSidebarIndex(sidebarIndex) { return sidebarIndex }

    // ── Navigation ────────────────────────────────────────────────────────
    function nextStep() {
        if (root.currentStep >= root.totalSteps - 1) return

        var next = root.currentStep + 1

        // "Write another" mode: jump directly to Writing after storage re-selection
        if (writeAnotherMode && root.currentStep === stepStorageSelection) {
            next = stepWriting
            writeAnotherMode = false
        }

        markStepPermissible(next)
        root.currentStep = next
        var comp = getStepComponent(next)
        if (comp) { wizardStack.clear(); wizardStack.push(comp) }
    }

    function previousStep() {
        if (root.currentStep <= 0) return
        root.currentStep--
        var comp = getStepComponent(root.currentStep)
        if (comp) { wizardStack.clear(); wizardStack.push(comp) }
    }

    function jumpToStep(stepIndex) {
        if (stepIndex < 0 || stepIndex >= root.totalSteps) return
        root.currentStep = stepIndex
        var comp = getStepComponent(stepIndex)
        if (comp) { wizardStack.clear(); wizardStack.push(comp) }
    }

    function invalidateVersionDependentSteps() {
        invalidateStepsFrom(stepStorageSelection)
        selectedStorageName = ""
        eveConfigured = false
    }

    // Called by DoneStep "Write Another" button — go back to storage selection,
    // skip customization, and jump straight to writing after drive is picked.
    function resetToWriteStep() {
        writeAnotherMode = true
        markStepPermissible(stepStorageSelection)
        jumpToStep(stepStorageSelection)
    }

    // ── Step component lookup ─────────────────────────────────────────────
    function getStepComponent(stepIndex) {
        switch (stepIndex) {
            case stepEveVersion:        return eveVersionStep
            case stepStorageSelection:  return storageSelectionStep
            case stepEveCustomization:  return eveCustomizationStep
            case stepWriting:           return writingStep
            case stepDone:              return doneStep
            default:                    return null
        }
    }

    // ── Main layout ───────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Sidebar ──────────────────────────────────────────────────────
        Rectangle {
            id: sidebar
            Layout.preferredWidth: root.sidebarWidthValue
            Layout.minimumWidth: Style.sidebarMinWidth
            Layout.maximumWidth: Style.sidebarMaxWidth
            Layout.fillHeight: true
            color: Style.sidebarBackgroundColour
            border.color: Style.sidebarBorderColour
            border.width: 0

            Flickable {
                id: sidebarScroll
                clip: true
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: sidebarBottom.top
                anchors.margins: Style.cardPadding
                contentWidth: -1
                contentHeight: sidebarColumn.implicitHeight
                z: 1

                ColumnLayout {
                    id: sidebarColumn
                    width: parent.width
                    spacing: Style.spacingXSmall
                    anchors.rightMargin: (sidebarScroll.contentHeight > sidebarScroll.height ? Style.scrollBarWidth : 0)

                    // Header
                    Text {
                        text: qsTr("Setup steps")
                        font.pointSize: Style.fontSizeHeading
                        font.family: Style.fontFamilyBold
                        font.bold: true
                        color: Style.sidebarTextOnInactiveColor
                        Layout.fillWidth: true
                        Layout.bottomMargin: Style.spacingSmall
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    // Step list
                    Repeater {
                        id: stepRepeater
                        model: root.stepNames

                        Rectangle {
                            id: stepItem
                            required property int index
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: Style.sidebarItemHeight
                            color: Style.transparent
                            radius: 0

                            property int _targetStep: root.getWizardStepFromSidebarIndex(stepItem.index)
                            property bool isActive: stepItem.index === root.getSidebarIndex(root.currentStep)
                            property bool isClickable: {
                                if (root.isWriting) return false
                                var bit = 1 << _targetStep
                                return (root.permissibleStepsBitmap & bit) !== 0 || _targetStep < root.currentStep
                            }

                            Rectangle {
                                id: headerRect
                                anchors.fill: parent
                                color: stepItem.isActive ? Style.sidebarActiveBackgroundColor : Style.transparent
                                border.color: stepItem.isActive ? Style.sidebarActiveBackgroundColor : Style.transparent
                                border.width: 1
                                radius: root.imageWriter.isEmbeddedMode() ? Style.sidebarItemBorderRadiusEmbedded : Style.sidebarItemBorderRadius
                                antialiasing: true
                                clip: true

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: stepItem.isClickable
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (!root.isWriting &&
                                            (root.isStepPermissible(stepItem._targetStep) || root.currentStep > stepItem._targetStep)) {
                                            root.jumpToStep(stepItem._targetStep)
                                        }
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Style.spacingSmall
                                    spacing: Style.spacingTiny

                                    MarqueeText {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        text: stepItem.modelData
                                        font.pointSize: Style.fontSizeSidebarItem
                                        font.family: Style.fontFamily
                                        color: stepItem.index > root.getSidebarIndex(root.currentStep)
                                               ? Style.sidebarTextDisabledColor
                                               : stepItem.isActive
                                                 ? Style.sidebarTextOnActiveColor
                                                 : Style.sidebarTextOnInactiveColor
                                    }
                                }
                            }
                        }
                    } // Repeater
                } // ColumnLayout
            } // Flickable

            // App Options button pinned to bottom of sidebar
            Item {
                id: sidebarBottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Style.buttonHeightStandard + Style.cardPadding * 2

                ImButton {
                    id: optionsButton
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Style.cardPadding
                    height: Style.buttonHeightStandard
                    text: qsTr("App Options")
                    accessibleDescription: qsTr("Open application settings")
                    activeFocusOnTab: true
                    onClicked: {
                        if (root.optionsPopup) {
                            if (!root.optionsPopup.wizardContainer) {
                                root.optionsPopup.wizardContainer = root
                            }
                            root.optionsPopup.initialize()
                            root.optionsPopup.open()
                        }
                    }
                }
            }
        } // sidebar Rectangle

        // ── Drag handle between sidebar and content ───────────────────────
        Item {
            id: dragHandle
            Layout.preferredWidth: Style.sidebarDragHandleWidth
            Layout.fillHeight: true

            readonly property bool isActive: dragHandleMouseArea.containsMouse || dragHandleMouseArea.pressed

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: parent.height * 0.75
                color: dragHandle.isActive ? Style.sidebarDragHandleHoverColor : Style.titleSeparatorColor
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Rectangle {
                anchors.fill: parent
                color: dragHandle.isActive ? Style.sidebarDragHandleHoverBackground : "transparent"
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            MouseArea {
                id: dragHandleMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.SplitHCursor

                property real startX: 0
                property real startWidth: 0

                onPressed: function(mouse) {
                    startX = mouse.x + dragHandle.x
                    startWidth = root.sidebarWidthValue
                }
                onPositionChanged: function(mouse) {
                    if (pressed) {
                        var delta = (mouse.x + dragHandle.x) - startX
                        root.sidebarWidthValue = root.clampSidebarWidth(startWidth + delta)
                    }
                }
                onReleased: root.saveSidebarWidth(root.sidebarWidthValue)
                onDoubleClicked: {
                    root.sidebarWidthValue = Style.sidebarWidth
                    root.saveSidebarWidth(Style.sidebarWidth)
                }
            }

            Accessible.role: Accessible.Separator
            Accessible.name: qsTr("Sidebar resize handle")
        }

        // ── Main content / wizard stack ───────────────────────────────────
        StackView {
            id: wizardStack
            Layout.fillWidth: true
            Layout.fillHeight: true

            initialItem: eveVersionStep

            pushEnter: Transition {
                PropertyAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
            }
            pushExit: Transition {
                PropertyAnimation { property: "opacity"; from: 1; to: 0; duration: 200 }
            }
            popEnter: Transition {
                PropertyAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
            }
            popExit: Transition {
                PropertyAnimation { property: "opacity"; from: 1; to: 0; duration: 200 }
            }

            onCurrentItemChanged: {
                if (currentItem) {
                    Qt.callLater(function() {
                        if (currentItem && currentItem.initialFocusItem) {
                            currentItem.initialFocusItem.forceActiveFocus()
                        } else if (currentItem && currentItem._focusableItems && currentItem._focusableItems.length > 0) {
                            currentItem._focusableItems[0].forceActiveFocus()
                        }
                    })
                }
            }
        }
    } // RowLayout

    // ── Step components ───────────────────────────────────────────────────

    Component {
        id: eveVersionStep
        EveVersionStep {
            id: eveVersionStepItem
            imageWriter: root.imageWriter
            wizardContainer: root
            showBackButton: false
            appOptionsButton: optionsButton
            onNextClicked: {
                eveVersionStepItem.syncState()   // commit version/arch/hv/platform + downloadUrl/size
                root.nextStep()
            }
        }
    }

    Component {
        id: storageSelectionStep
        StorageSelectionStep {
            imageWriter: root.imageWriter
            wizardContainer: root
            appOptionsButton: optionsButton
            onNextClicked: root.nextStep()
            onBackClicked: root.previousStep()
        }
    }

    Component {
        id: eveCustomizationStep
        EveCustomizationStep {
            imageWriter: root.imageWriter
            wizardContainer: root
            appOptionsButton: optionsButton
            onNextClicked: root.nextStep()
            onBackClicked: root.previousStep()
        }
    }

    Component {
        id: writingStep
        WritingStep {
            imageWriter: root.imageWriter
            wizardContainer: root
            showBackButton: true
            appOptionsButton: optionsButton
            onNextClicked: {
                if (isComplete) root.nextStep()
            }
            onBackClicked: root.previousStep()
        }
    }

    Component {
        id: doneStep
        DoneStep {
            imageWriter: root.imageWriter
            wizardContainer: root
            showBackButton: false
            nextButtonText: CommonStrings.finish
            appOptionsButton: optionsButton
            onNextClicked: root.wizardCompleted()
        }
    }
}
