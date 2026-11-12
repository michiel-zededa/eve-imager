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
        qsTr("Configuration"),
        qsTr("Write"),
        qsTr("Done")
    ]
    // ImIcon names, same order as stepNames
    readonly property var stepIcons: ["layers", "drive", "sliders", "download", "check-circle"]

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
    property double eveDownloadSize: 0        // download size in bytes (compressed size if eveIsCompressedImage; double avoids int32 overflow)
    property bool   eveIsCompressedImage: false // true = .raw.zst / legacy .img: eveDownloadSize is not the size written to the drive
    property double eveImageSize: 0           // size of the image as written to the drive, in bytes; 0 = not known
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
        onboardCertPath:    "",   // onboard.cert.pem
        onboardKeyPath:     "",   // onboard.key.pem
        authorizedKeys:     "",   // authorized_keys (SSH public key text)
        installDisk:        "",   // eve_install_disk grub param
        persistDisk:        "",   // eve_persist_disk grub param
        rebootAfterInstall: false // eve_reboot_after_install grub param
    })
    property bool eveConfigured: false

    // What the Configuration step adds to the drive, in one line (Write and Done pages)
    function eveConfigSummary() {
        if (root.eveIsIsoImage)
            return qsTr("Not applied (ISO image)")
        var c = root.eveConfig
        var parts = []
        if (c.controllerUrl)                parts.push(qsTr("Controller %1").arg(c.controllerUrl))
        if (c.networkMode === "static")     parts.push(c.staticIp ? qsTr("Static IP %1").arg(c.staticIp) : qsTr("Static IP"))
        if (c.proxyUrl)                     parts.push(qsTr("HTTP proxy"))
        if (c.wifiSsid)                     parts.push(qsTr("WiFi %1").arg(c.wifiSsid))
        if (c.installDisk)                  parts.push(qsTr("Install disk %1").arg(c.installDisk))
        if (c.persistDisk)                  parts.push(qsTr("/persist disk %1").arg(c.persistDisk))
        if (c.rebootAfterInstall)           parts.push(qsTr("Reboot after install"))
        return parts.length > 0 ? parts.join(" · ") : qsTr("None")
    }

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
            // Restore the appearance choice (light / dark / follow system)
            var savedTheme = imageWriter.getStringSetting("theme")
            if (savedTheme === "light" || savedTheme === "dark" || savedTheme === "system") {
                Style.themeMode = savedTheme
            }
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
    // A finished write (succeeded, failed or cancelled) stays recorded in the
    // writer until it is told otherwise. Clear it whenever the user moves to
    // any step other than Done, so that the write step always starts from a
    // clean summary instead of showing the previous run's outcome.
    function forgetFinishedWrite(targetStep) {
        if (targetStep !== stepDone) {
            imageWriter.resetWriteState()
        }
    }

    function nextStep() {
        if (root.currentStep >= root.totalSteps - 1) return

        var next = root.currentStep + 1

        // "Write another" mode: jump directly to Writing after storage re-selection
        if (writeAnotherMode && root.currentStep === stepStorageSelection) {
            next = stepWriting
            writeAnotherMode = false
        }

        // ISO images: skip the customization step — config cannot be applied to ISOs
        if (next === stepEveCustomization && root.eveIsIsoImage) {
            next = stepWriting
        }

        markStepPermissible(next)
        forgetFinishedWrite(next)
        root.currentStep = next
        var comp = getStepComponent(next)
        if (comp) { wizardStack.clear(); wizardStack.push(comp) }
    }

    function previousStep() {
        if (root.currentStep <= 0) return
        var prev = root.currentStep - 1

        // ISO images: skip back over the customization step
        if (prev === stepEveCustomization && root.eveIsIsoImage) {
            prev = stepStorageSelection
        }

        forgetFinishedWrite(prev)
        root.currentStep = prev
        var comp = getStepComponent(prev)
        if (comp) { wizardStack.clear(); wizardStack.push(comp) }
    }

    function jumpToStep(stepIndex) {
        if (stepIndex < 0 || stepIndex >= root.totalSteps) return
        forgetFinishedWrite(stepIndex)
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
    // Appearance: "system" follows the OS, "light" and "dark" force a theme.
    function cycleThemeMode() {
        var next = Style.themeMode === "system" ? "light" : Style.themeMode === "light" ? "dark" : "system"
        Style.themeMode = next
        if (imageWriter) imageWriter.setSetting("theme", next)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Top bar: ZEDEDA wordmark, product name, app-level actions ─────
        Item {
            id: topBar
            Layout.fillWidth: true
            Layout.preferredHeight: Style.topBarHeight

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.cardPadding
                anchors.rightMargin: Style.spacingSmallPlus
                spacing: Style.spacingSmall

                Image {
                    id: zededaWordmark
                    // 137x25 artwork; one file per ink colour because the SVG
                    // loader cannot recolour it
                    source: Style.dark ? "../icons/zededa-wordmark-on-dark.svg" : "../icons/zededa-wordmark-on-light.svg"
                    readonly property int logoWidth: Style.scaled(104)
                    readonly property int logoHeight: Math.round(logoWidth * 25 / 137)
                    Layout.preferredWidth: logoWidth
                    Layout.preferredHeight: logoHeight
                    Layout.alignment: Qt.AlignVCenter
                    sourceSize: Qt.size(Math.round(logoWidth * Screen.devicePixelRatio), Math.round(logoHeight * Screen.devicePixelRatio))
                    fillMode: Image.PreserveAspectFit
                    Accessible.role: Accessible.Graphic
                    Accessible.name: "ZEDEDA"
                }

                Text {
                    text: qsTr("EVE Imager")
                    font.family: Style.fontFamily
                    font.pointSize: Style.fontSizeFormLabel
                    font.weight: Style.fontWeightMedium
                    color: Style.text
                    Layout.leftMargin: Style.spacingMedium
                    Layout.alignment: Qt.AlignVCenter
                }

                Item { Layout.fillWidth: true }

                ImButton {
                    id: optionsButton
                    Layout.preferredHeight: Style.scaled(34)
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: implicitContentWidth + leftPadding + rightPadding
                    leftPadding: Style.spacingMedium
                    rightPadding: Style.spacingMedium
                    text: qsTr("App options")
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

                ImIconButton {
                    id: appearanceButton
                    Layout.alignment: Qt.AlignVCenter
                    iconName: Style.themeMode === "light" ? "sun" : Style.themeMode === "dark" ? "moon" : "monitor"
                    label: Style.themeMode === "light" ? qsTr("Appearance: light")
                         : Style.themeMode === "dark" ? qsTr("Appearance: dark")
                         : qsTr("Appearance: follow system")
                    onClicked: root.cycleThemeMode()
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: Style.border
            }
        }

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 0

        // ── Sidebar ──────────────────────────────────────────────────────
        Rectangle {
            id: sidebar
            Layout.preferredWidth: root.sidebarWidthValue
            Layout.minimumWidth: Style.sidebarMinWidth
            Layout.maximumWidth: Style.sidebarMaxWidth
            Layout.fillHeight: true
            color: Style.sidebarBackgroundColour

            // ── Product heading ──────────────────────────────────────────
            ColumnLayout {
                id: sidebarHead
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: Style.cardPadding
                anchors.leftMargin: Style.cardPadding + Style.spacingXSmall
                anchors.rightMargin: Style.spacingSmall
                spacing: Style.spacingXXSmall

                Text {
                    text: qsTr("EVE Imager")
                    font.family: Style.fontFamily
                    font.pointSize: Style.fontSizeHeading
                    font.weight: Style.fontWeightSemiBold
                    color: Style.text
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Text {
                    text: qsTr("Write EVE-OS installers to USB")
                    font.family: Style.fontFamily
                    font.pointSize: Style.fontSizeDescription
                    color: Style.muted
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
            }

            Flickable {
                id: sidebarScroll
                clip: true
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: sidebarHead.bottom
                anchors.bottom: sidebarBottom.top
                anchors.topMargin: Style.spacingLarge
                anchors.leftMargin: Style.spacingSmallPlus
                anchors.rightMargin: Style.spacingXSmall
                contentWidth: -1
                contentHeight: sidebarColumn.implicitHeight
                z: 1

                ColumnLayout {
                    id: sidebarColumn
                    width: parent.width
                    spacing: Style.spacingXXSmall
                    anchors.rightMargin: (sidebarScroll.contentHeight > sidebarScroll.height ? Style.scrollBarWidth : 0)

                    // Section label
                    Text {
                        text: qsTr("Setup steps")
                        font.pointSize: Math.round(Style.fontSizeDescription * 0.92)
                        font.family: Style.fontFamily
                        font.weight: Style.fontWeightSemiBold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1.1
                        color: Style.muted
                        Layout.fillWidth: true
                        Layout.leftMargin: Style.spacingSmallPlus
                        Layout.bottomMargin: Style.spacingTiny
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
                            // A step the user has already been through
                            property bool isDone: stepItem.index < root.getSidebarIndex(root.currentStep)
                            property bool isClickable: {
                                if (root.isWriting) return false
                                var bit = 1 << _targetStep
                                return (root.permissibleStepsBitmap & bit) !== 0 || _targetStep < root.currentStep
                            }

                            Rectangle {
                                id: headerRect
                                anchors.fill: parent
                                color: stepItem.isActive ? Style.sidebarActiveBackgroundColor
                                       : (stepMouseArea.containsMouse && stepItem.isClickable) ? Style.surface2 : Style.transparent
                                radius: root.imageWriter.isEmbeddedMode() ? Style.sidebarItemBorderRadiusEmbedded : Style.sidebarItemBorderRadius
                                antialiasing: true
                                clip: true

                                MouseArea {
                                    id: stepMouseArea
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
                                    anchors.leftMargin: Style.spacingSmallPlus
                                    anchors.rightMargin: Style.spacingSmall
                                    spacing: Style.spacingSmallPlus

                                    ImIcon {
                                        Layout.alignment: Qt.AlignVCenter
                                        size: Style.scaled(18)
                                        name: stepItem.isDone ? "check" : root.stepIcons[stepItem.index]
                                        color: stepItem.isActive ? Style.sidebarTextOnActiveColor
                                               : stepItem.isDone ? Style.ok : Style.muted
                                    }

                                    MarqueeText {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        text: stepItem.modelData
                                        font.pointSize: Style.fontSizeSidebarItem
                                        font.family: Style.fontFamily
                                        font.weight: stepItem.isActive ? Style.fontWeightMedium : Font.Normal
                                        color: stepItem.isActive ? Style.sidebarTextOnActiveColor
                                               : stepItem.isDone ? Style.sidebarTextOnInactiveColor
                                               : Style.sidebarTextDisabledColor
                                    }
                                }
                            }
                        }
                    } // Repeater
                } // ColumnLayout
            } // Flickable

            // App version pinned to the bottom of the sidebar
            Item {
                id: sidebarBottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: versionText.implicitHeight + Style.spacingMedium * 2

                Text {
                    id: versionText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.cardPadding + Style.spacingXSmall
                    anchors.rightMargin: Style.spacingSmall
                    text: root.imageWriter ? root.imageWriter.constantVersion() : ""
                    font.family: Style.fontFamilyMono
                    font.pointSize: Math.round(Style.fontSizeDescription * 0.92)
                    color: Style.muted
                    elide: Text.ElideRight
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
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: parent.height
                color: dragHandle.isActive ? Style.accent : Style.border
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
    } // ColumnLayout (top bar + body)

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
