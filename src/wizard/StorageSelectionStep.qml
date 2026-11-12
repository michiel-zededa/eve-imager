/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2020 Raspberry Pi Ltd
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
    
    title: qsTr("Select storage device")
    subtitle: qsTr("Choose the USB drive to write the installer to.")
    showNextButton: true
    nextButtonEnabled: wizardContainer && wizardContainer.selectedStorageName && wizardContainer.selectedStorageName.length > 0  // Disabled until user selects a storage device
    
    // Forward the nextClicked signal as next() function
    // Only auto-advance if no system drive confirmation dialog is needed
    function next() {
        root.nextClicked()
    }
    
    // Conditional next function for keyboard auto-advance
    // Only auto-advance for non-system drives
    function conditionalNext() {
        // Check if current selection is a system drive
        if (dstlist.currentIndex >= 0) {
            var currentItem = dstlist.itemAtIndex(dstlist.currentIndex)
            if (currentItem && currentItem.isSystem) {
                // Don't auto-advance for system drives - let the confirmation dialog handle it
                return
            }
            
            // Fallback: check model directly when itemAtIndex returns null
            // (e.g., when using screen readers on Windows)
            if (!currentItem) {
                var model = root.imageWriter.getDriveList()
                if (model && dstlist.currentIndex < model.rowCount()) {
                    var modelIndex = model.index(dstlist.currentIndex, 0)
                    if (modelIndex && modelIndex.valid) {
                        var isSystemRole = 0x107
                        var isSystem = model.data(modelIndex, isSystemRole)
                        if (isSystem) {
                            // Don't auto-advance for system drives
                            return
                        }
                    }
                }
            }
        }
        // Safe to auto-advance for non-system drives
        root.nextClicked()
    }
    
    property alias dstlist: dstlist
    property string selectedDeviceName: ""
    property bool hasValidStorageOptions: false
    property bool hasAnyDevices: false
    property bool hasOnlyReadOnlyDevices: false
    property string enumerationErrorMessage: ""
    // True while the list shows at least one row (selectable or not)
    property bool hasAnyVisibleRows: false
    
    Component.onCompleted: {
        // Register the ListView for keyboard navigation
        root.registerFocusGroup("storage_list", function(){
            return [dstlist, filterSystemDrives]
        }, 0)
        
        // Set the initial focus item to the ListView
        // Initial focus will automatically go to title, then first control (handled by WizardStepBase)
        
        // Initialize hasValidStorageOptions
        root.updateStorageStatus()
    }
    
    // Watch for device removal - when selectedStorageName becomes empty, clear the currentIndex
    // This ensures that when a device is re-inserted, it won't appear highlighted but not actually selected
    Connections {
        target: wizardContainer
        function onSelectedStorageNameChanged() {
            if (!wizardContainer.selectedStorageName || wizardContainer.selectedStorageName.length === 0) {
                // Device was removed - clear the visual selection and ensure next button is disabled
                dstlist.currentIndex = -1
                root.selectedDeviceName = ""
                root.nextButtonEnabled = false
            }
        }
    }
    
    // Watch for drive enumeration errors from the model
    // This handles cases where the OS can't enumerate drives (permissions, driver issues, etc.)
    Connections {
        target: root.imageWriter ? root.imageWriter.getDriveList() : null
        function onEnumerationError(errorMessage) {
            root.enumerationErrorMessage = errorMessage || ""
            if (errorMessage) {
                console.warn("Drive enumeration error:", errorMessage)
            }
        }
    }
    
    // Removed drive list polling calls; backend handles device updates
    
    // Content
    content: [
    ColumnLayout {
        anchors.fill: parent
        spacing: Style.spacingSmallPlus

        // Error banner for drive enumeration failures
        ImBanner {
            id: enumerationErrorBanner
            Layout.fillWidth: true
            visible: root.enumerationErrorMessage.length > 0
            kind: "err"
            text: qsTr("Could not list storage devices: %1").arg(root.enumerationErrorMessage)
            Accessible.role: Accessible.AlertMessage
            Accessible.name: qsTr("Error: Could not list storage devices. %1").arg(root.enumerationErrorMessage)
        }

        // The drive list sits in a card: a header row with the filter, then
        // one row per drive.
        ImCard {
            Layout.fillWidth: true
            Layout.fillHeight: true
            padding: 0
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Style.cardPadding
                Layout.rightMargin: Style.spacingSmall
                Layout.preferredHeight: Style.scaled(48)
                spacing: Style.spacingSmall

                Text {
                    text: qsTr("Drives")
                    font.family: Style.fontFamily
                    font.pointSize: Style.fontSizeCaption
                    font.weight: Style.fontWeightSemiBold
                    font.letterSpacing: 1.1
                    font.capitalization: Font.AllUppercase
                    color: Style.muted
                    Accessible.ignored: true
                }

                Item { Layout.fillWidth: true }

                ImCheckBox {
                    id: filterSystemDrives
                    checked: true
                    text: qsTr("Exclude system drives")
                    Accessible.description: qsTr("When checked, system drives are hidden from the list. Uncheck to show all drives including system drives.")

                    onToggled: {
                        if (!checked) {
                            // If warnings are disabled, bypass the confirmation dialog
                            if (root.wizardContainer && root.wizardContainer.disableWarnings) {
                                // Leave checkbox unchecked and continue showing system drives
                                dstlist.forceActiveFocus()
                            } else {
                                // Ask for stern confirmation before disabling filtering
                                confirmUnfilterPopup.open()
                            }
                        }
                    }

                    // Update storage status whenever checked state changes (from any source)
                    onCheckedChanged: {
                        // Defer the update to allow the model to update first
                        Qt.callLater(root.updateStorageStatus)
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Style.border
            }

        // Storage device list fills available space
        SelectionListView {
            id: dstlist
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 1
            Layout.rightMargin: 1
            Layout.bottomMargin: Style.sectionBorderRadius / 2
            model: root.imageWriter.getDriveList()
            delegate: dstdelegate
            keyboardAutoAdvance: true
            nextFunction: root.conditionalNext
            isItemSelectableFunction: root.isStorageItemSelectable
            accessibleName: {
                // Count only visible and selectable devices
                var selectableCount = 0
                for (var i = 0; i < dstlist.count; i++) {
                    if (root.isStorageItemSelectable(i)) {
                        selectableCount++
                    }
                }
                
                var baseName = qsTr("Storage device list")
                
                // Add item count (only selectable items)
                if (selectableCount === 0) {
                    baseName += ". " + qsTr("No devices")
                } else if (selectableCount === 1) {
                    baseName += ". " + qsTr("1 device")
                } else {
                    baseName += ". " + qsTr("%1 devices").arg(selectableCount)
                }
                
                baseName += ". " + qsTr("Use arrow keys to navigate, Enter or Space to select")
                
                // Include the status message if there are no valid options
                if (!root.hasValidStorageOptions) {
                    var statusMsg = root.getStorageStatusMessage()
                    baseName += ". " + statusMsg
                }
                return baseName
            }
            accessibleDescription: ""
            
            // Disable ListView's built-in highlight since delegate handles its own highlighting
            highlight: Item {}
            highlightFollowsCurrentItem: false
            
            onItemSelected: function(index, item) {
                if (index >= 0 && index < dstlist.count) {
                    // Try to use the delegate item if available
                    if (item && typeof item.selectDrive === "function") {
                        item.selectDrive()
                    } else {
                        // Fallback: get data directly from the model
                        // This handles cases where itemAtIndex() returns null
                        // (e.g., when using screen readers on Windows where
                        // delegates may not be instantiated)
                        root.selectDriveByIndex(index)
                    }
                }
            }
            
            onItemDoubleClicked: function(index, item) {
                // First select the item
                if (index >= 0 && index < count && item && typeof item.selectDrive === "function") {
                    item.selectDrive()
                    
                    // Then advance to next step if possible (same as pressing Return)
                    Qt.callLater(function() {
                        if (root.nextButtonEnabled) {
                            root.nextClicked()
                        }
                    })
                }
            }

            // Update storage status when device list changes
            onCountChanged: {
                root.updateStorageStatus()
            }
            
            // Shown when there is nothing to pick from. Also read by screen readers.
            Label {
                id: noDevicesLabel
                anchors.fill: parent
                anchors.margins: Style.cardPadding
                visible: !root.hasValidStorageOptions && !root.hasAnyVisibleRows
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
                font.family: Style.fontFamily
                font.pointSize: Style.fontSizeFormLabel
                color: Style.muted
                text: {
                    // Check for enumeration error first
                    if (root.enumerationErrorMessage.length > 0) {
                        return qsTr("Could not list storage devices: %1").arg(root.enumerationErrorMessage)
                    } else if (!root.hasAnyDevices) {
                        return qsTr("No storage devices found")
                    } else if (root.hasOnlyReadOnlyDevices) {
                        if (filterSystemDrives.checked) {
                            return qsTr("All visible devices are read-only.\nTry connecting a new device, or uncheck\n'Exclude system drives' above.")
                        } else {
                            return qsTr("All devices are read-only.\nPlease connect a writable storage device.")
                        }
                    } else {
                        return qsTr("All devices are hidden by the filter.\nUncheck 'Exclude system drives' above\nto show system drives.")
                    }
                }
                Accessible.role: Accessible.StatusBar
                Accessible.name: text
                Accessible.ignored: false
                
                // Force accessibility update when text changes
                onTextChanged: {
                    if (visible) {
                        // Briefly toggle focus to force screen reader update
                        Accessible.ignored = true
                        Qt.callLater(function() {
                            Accessible.ignored = false
                        })
                    }
                }
                
                // Announce when becomes visible
                onVisibleChanged: {
                    if (visible) {
                        // Small delay to ensure the text is set before announcing
                        Qt.callLater(function() {
                            if (visible) {
                                forceActiveFocus()
                            }
                        })
                    }
                }
            }
        }
        } // ImCard

        // What the image needs, so the size limits in the list make sense
        Text {
            Layout.fillWidth: true
            visible: root.wizardContainer && root.wizardContainer.eveImageSize > 0
            text: visible ? qsTr("The selected image takes %1 on the drive. Everything on the drive you choose will be erased.")
                            .arg(root.imageWriter.formatSize(root.wizardContainer.eveImageSize))
                          : ""
            font.family: Style.fontFamily
            font.pointSize: Style.fontSizeDescription
            color: Style.muted
            wrapMode: Text.WordWrap
        }
    }
    ]
    
    // Storage delegate component
    Component {
        id: dstdelegate
        
        Item {
            id: dstitem
            
            required property int index
            required property string device
            required property string description
            required property string size
            required property bool isUsb
            required property bool isScsi
            required property bool isReadOnly
            required property bool isSystem
            required property var mountpoints
            required property QtObject modelData
            property bool isRpiboot: modelData && typeof modelData.isRpiboot !== "undefined" ? modelData.isRpiboot : false
            property bool isFastbootStorage: modelData && typeof modelData.isFastbootStorage !== "undefined" ? modelData.isFastbootStorage : false
            property string fastbootStorageType: modelData && typeof modelData.fastbootStorageType !== "undefined" ? modelData.fastbootStorageType : ""

            readonly property bool shouldHide: isSystem && filterSystemDrives.checked
            // The drive cannot hold the selected image (only when the image size is known)
            readonly property bool tooSmall: !isRpiboot && !isFastbootStorage && root.isTooSmallForImage(size)
            readonly property bool unselectable: (isReadOnly && !isRpiboot && !isFastbootStorage) || tooSmall
            
            // Accessibility properties
            Accessible.role: Accessible.ListItem
            Accessible.name: dstitem.description + ". " + imageWriter.formatSize(parseFloat(dstitem.size)) + (dstitem.mountpoints.length > 0 ? ". " + qsTr("Mounted as %1").arg(dstitem.mountpoints.join(", ")) : "") + (dstitem.tooSmall ? ". " + root.tooSmallText() : (dstitem.unselectable ? ". " + qsTr("Read-only") : ""))
            Accessible.focusable: true
            Accessible.ignored: false
            
            // Function called by keyboard selection
            function selectDrive() {
                if (!unselectable) {
                    root.selectDstItem(dstitem)
                }
            }
            
            width: dstlist.width
            height: shouldHide ? 0 : Style.scaled(68)
            visible: !shouldHide

            readonly property bool isCurrent: dstlist.currentIndex === dstitem.index
            // Chosen for writing (not just the keyboard cursor)
            readonly property bool isChosen: isCurrent && root.wizardContainer
                                             && root.wizardContainer.selectedStorageName.length > 0
                                             && root.selectedDeviceName === (dstitem.description || dstitem.device)

            Rectangle {
                id: dstbgrect
                anchors.fill: parent
                color: dstitem.isCurrent ? Style.listViewHighlightColor :
                       (dstMouseArea.containsMouse && !dstitem.unselectable ? Style.listViewHoverRowBackgroundColor : "transparent")
                anchors.rightMargin: (dstlist.contentHeight > dstlist.height ? Style.scrollBarWidth : 0)
                Accessible.ignored: true

                // Divider between rows
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Style.border
                }
                
                MouseArea {
                    id: dstMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: dstitem.unselectable ? Qt.ForbiddenCursor : Qt.PointingHandCursor
                    enabled: !dstitem.unselectable
                    
                    onClicked: {
                        if (!dstitem.unselectable) {
                            dstlist.currentIndex = dstitem.index
                            root.selectDstItem(dstitem)
                        }
                    }
                    
                    onDoubleClicked: {
                        if (!dstitem.unselectable) {
                            // Double-click acts like pressing Return - select and advance
                            dstlist.itemDoubleClicked(dstitem.index, dstitem)
                        }
                    }
                }
                
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.cardPadding
                    anchors.rightMargin: Style.cardPadding
                    spacing: Style.spacingSmallPlus
                    
                    // Storage icon in a rounded tile
                    Rectangle {
                        Layout.preferredWidth: Style.scaled(38)
                        Layout.preferredHeight: Style.scaled(38)
                        radius: Style.controlBorderRadius
                        color: dstitem.isCurrent ? Style.surface : Style.surface2

                        ImIcon {
                            anchors.centerIn: parent
                            size: Style.scaled(20)
                            color: dstitem.isCurrent ? Style.accentText : Style.muted
                            name: dstitem.isFastbootStorage ? (dstitem.fastbootStorageType === "nvme" ? "drive" : "sd-card")
                                : dstitem.isUsb || dstitem.isRpiboot ? "usb"
                                : dstitem.isScsi ? "drive"
                                : "sd-card"
                        }
                    }
                    
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Style.spacingXXSmall
                        
                        MarqueeText {
                            text: dstitem.description
                            font.pointSize: Style.fontSizeFormLabel
                            font.family: Style.fontFamily
                            font.weight: Style.fontWeightMedium
                            color: dstitem.unselectable ? Style.muted : Style.text
                            Layout.fillWidth: true
                            Accessible.ignored: true
                        }
                        
                        MarqueeText {
                            text: {
                                var t = dstitem.isRpiboot ? qsTr("Ready for USB boot")
                                                          : imageWriter.formatSize(parseFloat(dstitem.size))
                                if (dstitem.mountpoints.length > 0)
                                    t += " · " + qsTr("Mounted as %1").arg(dstitem.mountpoints.join(", "))
                                return t
                            }
                            font.pointSize: Style.fontSizeDescription
                            font.family: Style.fontFamily
                            color: Style.muted
                            Layout.fillWidth: true
                            Accessible.ignored: true
                        }
                    }
                    
                    // Status: selected / too small / read-only
                    ImPill {
                        visible: dstitem.unselectable || dstitem.isChosen
                        kind: dstitem.tooSmall ? "err" : dstitem.unselectable ? "warn" : "neutral"
                        text: dstitem.tooSmall ? root.tooSmallText()
                            : dstitem.unselectable ? qsTr("Read-only")
                            : qsTr("Selected")
                        Accessible.ignored: true
                    }
                }
            }
        }
    }
    
    // True if a drive of this size (bytes) cannot hold the selected image.
    // Always false while the image size is not known (0).
    function isTooSmallForImage(deviceSize) {
        var need = root.wizardContainer ? root.wizardContainer.eveImageSize : 0
        var have = parseFloat(deviceSize)
        return need > 0 && have > 0 && have < need
    }

    function tooSmallText() {
        return qsTr("Too small: the image needs %1").arg(imageWriter.formatSize(root.wizardContainer.eveImageSize))
    }

    // Storage selection function
    function selectDstItem(dstitem) {
        if (dstitem.unselectable) {
            return
        }

        if (dstitem.isSystem) {
            // Show stern confirmation dialog requiring typing the name
            systemDriveConfirm.driveName = dstitem.description
            systemDriveConfirm.device = dstitem.device
            systemDriveConfirm.deviceSize = dstitem.size
            systemDriveConfirm.sizeStr = imageWriter.formatSize(parseFloat(dstitem.size))
            systemDriveConfirm.mountpoints = dstitem.mountpoints
            systemDriveConfirm.open()
            return
        }

        // Fastboot storage devices use setFastbootDevice
        if (dstitem.isFastbootStorage && typeof imageWriter.setFastbootDevice === "function") {
            imageWriter.setFastbootDevice(dstitem.device, dstitem.size)
        } else if (dstitem.isRpiboot && typeof imageWriter.setRpibootDevice === "function") {
            imageWriter.setRpibootDevice(dstitem.device)
        } else {
            imageWriter.setDst(dstitem.device, dstitem.size)
        }
        selectedDeviceName = dstitem.description || dstitem.device
        root.wizardContainer.selectedStorageName = dstitem.description || dstitem.device

        // Do not auto-advance; enable Next
        root.nextButtonEnabled = true
    }
    
    // Select drive by model index (used when delegate item is not available,
    // e.g., when using screen readers where itemAtIndex() returns null)
    function selectDriveByIndex(index) {
        var model = root.imageWriter.getDriveList()
        if (!model || index < 0 || index >= model.rowCount()) {
            return
        }
        
        var modelIndex = model.index(index, 0)
        if (!modelIndex || !modelIndex.valid) {
            return
        }
        
        // Role values from DriveListModel (Qt::UserRole + 1, etc.)
        var deviceRole = 0x101
        var descriptionRole = 0x102
        var sizeRole = 0x103
        var isReadOnlyRole = 0x106
        var isSystemRole = 0x107
        var mountpointsRole = 0x108
        var isFastbootStorageRole = 0x10B

        var isReadOnly = model.data(modelIndex, isReadOnlyRole)
        if (isReadOnly) {
            return  // Can't select read-only devices
        }
        if (root.isTooSmallForImage(model.data(modelIndex, sizeRole))) {
            return  // Can't select devices the image does not fit on
        }

        var isSystem = model.data(modelIndex, isSystemRole)
        var device = model.data(modelIndex, deviceRole)
        var description = model.data(modelIndex, descriptionRole)
        var size = model.data(modelIndex, sizeRole)
        var mountpoints = model.data(modelIndex, mountpointsRole) || []
        var isFastbootStorage = model.data(modelIndex, isFastbootStorageRole) || false

        // Create a mock item object with the required properties
        var mockItem = {
            unselectable: isReadOnly,
            isSystem: isSystem,
            isFastbootStorage: isFastbootStorage,
            isRpiboot: false,
            device: device,
            description: description,
            size: size,
            mountpoints: mountpoints
        }
        
        root.selectDstItem(mockItem)
    }

    // Check if a storage item at the given index is selectable (not read-only and not hidden)
    function isStorageItemSelectable(index) {
        var model = root.imageWriter.getDriveList()
        if (!model || index < 0 || index >= model.rowCount()) {
            return false
        }
        
        var sizeRole = 0x103
        var isReadOnlyRole = 0x106
        var isSystemRole = 0x107
        
        var idx = model.index(index, 0)
        var isReadOnly = model.data(idx, isReadOnlyRole)
        var isSystem = model.data(idx, isSystemRole)
        
        // Item is selectable if it's not read-only, large enough for the image,
        // and either not a system drive or filter is off
        var shouldHide = isSystem && filterSystemDrives.checked
        return !isReadOnly && !shouldHide && !root.isTooSmallForImage(model.data(idx, sizeRole))
    }
    
    // Check if there are any selectable items in the list
    function hasSelectableItems() {
        var model = root.imageWriter.getDriveList()
        if (!model || model.rowCount() === 0) {
            return false
        }
        
        for (var i = 0; i < model.rowCount(); i++) {
            if (isStorageItemSelectable(i)) {
                return true
            }
        }
        return false
    }
    
    // Update storage status properties for accessibility messages
    function updateStorageStatus() {
        var model = root.imageWriter.getDriveList()
        root.hasValidStorageOptions = hasSelectableItems()
        root.hasAnyDevices = model && model.rowCount() > 0

        // Rows that are actually drawn: everything except filtered system drives
        var anyVisible = false
        if (root.hasAnyDevices) {
            for (var r = 0; r < model.rowCount(); r++) {
                var isSys = model.data(model.index(r, 0), 0x107)
                if (!(isSys && filterSystemDrives.checked)) {
                    anyVisible = true
                    break
                }
            }
        }
        root.hasAnyVisibleRows = anyVisible
        
        // Check if we only have read-only devices
        if (root.hasAnyDevices && !root.hasValidStorageOptions) {
            var isReadOnlyRole = 0x106
            var allReadOnly = true
            for (var i = 0; i < model.rowCount(); i++) {
                var idx = model.index(i, 0)
                var isReadOnly = model.data(idx, isReadOnlyRole)
                if (!isReadOnly) {
                    allReadOnly = false
                    break
                }
            }
            root.hasOnlyReadOnlyDevices = allReadOnly
        } else {
            root.hasOnlyReadOnlyDevices = false
        }
    }
    
    // Get the storage status message for accessibility
    function getStorageStatusMessage() {
        // Check for enumeration error first
        if (root.enumerationErrorMessage.length > 0) {
            return qsTr("Could not list storage devices: %1. This may be a permissions issue. Try running the application with administrator privileges.").arg(root.enumerationErrorMessage)
        } else if (!root.hasAnyDevices) {
            return qsTr("No storage devices found. Please connect a storage device to continue.")
        } else if (root.hasOnlyReadOnlyDevices) {
            if (filterSystemDrives.checked) {
                return qsTr("No valid storage devices are currently available. All visible devices are read-only. Try connecting a new storage device, or uncheck 'Exclude system drives' to show hidden system drives.")
            } else {
                return qsTr("No valid storage devices are currently available. All devices are read-only. Please connect a writable storage device to continue.")
            }
        } else {
            return qsTr("No valid storage devices are currently available. Uncheck 'Exclude system drives' to show hidden system drives, or connect a new storage device.")
        }
    }
    // Stern confirmation when disabling system drive filtering
    ConfirmUnfilterDialog {
        id: confirmUnfilterPopup
        imageWriter: root.imageWriter
        overlayParent: root.wizardContainer && root.wizardContainer.overlayRootRef ? root.wizardContainer.overlayRootRef : (root.Window.window ? root.Window.window.overlayRootItem : null)
        onConfirmed: {
            // user chose to disable filter; leave checkbox unchecked
            // updateStorageStatus will be called via onCheckedChanged
        }
        onCancelled: {
            // Re-enable the filter checkbox and keep system drives hidden
            filterSystemDrives.checked = true
            // updateStorageStatus will be called via onCheckedChanged
        }
        onClosed: {
            if (filterSystemDrives.checked === false) {
                dstlist.forceActiveFocus()
            } else {
                filterSystemDrives.forceActiveFocus()
            }
        }
    }

    // Confirmation when selecting a system drive: type the exact name
    ConfirmSystemDriveDialog {
        id: systemDriveConfirm
        imageWriter: root.imageWriter
        overlayParent: root.wizardContainer && root.wizardContainer.overlayRootRef ? root.wizardContainer.overlayRootRef : (root.Window.window ? root.Window.window.overlayRootItem : null)
        onConfirmed: {
            root.imageWriter.setDst(systemDriveConfirm.device, systemDriveConfirm.deviceSize)
            root.selectedDeviceName = systemDriveConfirm.driveName || systemDriveConfirm.device
            root.wizardContainer.selectedStorageName = systemDriveConfirm.driveName || systemDriveConfirm.device
            // Re-enable filtering after selection via confirmation path
            filterSystemDrives.checked = true
            // updateStorageStatus will be called via onCheckedChanged
            // Enable Next
            root.nextButtonEnabled = true
            // Auto-advance after explicit confirmation on a system drive
            root.next()
        }
        onCancelled: {
            // no-op
        }
    }
} 
