/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025-2026 ZEDEDA, Inc.
 *
 * Step 2 — EVE-OS device configuration.
 *
 * Two views of one set of settings (WizardContainer.eveConfig):
 *   Simple    controller, WiFi, "my network uses a proxy"
 *   Advanced  everything, in sections that open and close
 * Settings made in Advanced stay in effect in Simple, which says so.
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
    subtitle: advanced ? qsTr("Optional. Open a section to change its settings.")
                       : qsTr("Optional. Anything you leave empty uses the EVE-OS default.")

    showBackButton: true
    showNextButton: true
    nextButtonEnabled: true

    readonly property var cfg: wizardContainer.eveConfig
    readonly property bool advanced: wizardContainer.eveConfigMode === "advanced"
    // A bootstrap config from the controller replaces the network settings
    // An installer ISO takes the configuration, but not the installer options
    readonly property bool isIso: wizardContainer.eveIsIsoImage
    readonly property bool bootstrapActive: cfg.bootstrapConfigPath.length > 0
    // FR201 is a Compute Module 4 board: arm64 only. A local file is not checked.
    // Message from the last check of the settings; "" if they are fine
    property string configError: ""

    // ── Settings ──────────────────────────────────────────────────────────────

    function setCfg(key, value) {
        // A new object each time, so that everything bound to cfg follows
        var c = Object.assign({}, root.wizardContainer.eveConfig)
        c[key] = value
        root.wizardContainer.eveConfig = c
        root.configError = ""
    }

    // Called by the wizard before it leaves this step
    function checkConfig() {
        root.configError = root.imageWriter.eveConfigError(root.wizardContainer.eveConfig)
        if (root.configError.length > 0) {
            formFlickable.contentY = 0
            return false
        }
        return true
    }

    // ── Files ─────────────────────────────────────────────────────────────────

    readonly property string certFilter: qsTr("Certificates (*.pem *.crt *.cer *.der);;All files (*)")

    function pickFile(title, filter, callback) {
        if (root.imageWriter.nativeFileDialogAvailable()) {
            var path = root.imageWriter.getNativeOpenFileName(title, "", filter)
            if (path)
                callback(path)
        } else {
            fallbackDialog.dialogTitle = title
            fallbackDialog.nameFilters = filter.split(";;")
            fallbackDialog.picked = callback
            fallbackDialog.open()
        }
    }

    function urlToPath(u) {
        var s = u.toString()
        if (s.startsWith("file://")) {
            s = s.substring(7)
            if (/^\/[A-Za-z]:/.test(s))     // file:///C:/… on Windows
                s = s.substring(1)
        }
        return decodeURIComponent(s)
    }

    // What to say under a chosen certificate file
    function certDetail(path) {
        if (!path)
            return { text: "", kind: "" }
        var info = root.imageWriter.certificateInfo(path)
        if (!info.ok)
            return { text: info.error || qsTr("This file cannot be used."), kind: "err" }
        var name = info.subject || ""
        if (info.count > 1)
            name = name ? qsTr("%1 and %2 more").arg(name).arg(info.count - 1) : qsTr("%1 certificates").arg(info.count)
        if (info.expired)
            return { text: (name ? name + " · " : "") + qsTr("expired on %1").arg(info.expires), kind: "warn" }
        if (info.expires)
            return { text: (name ? name + " · " : "") + qsTr("valid until %1").arg(info.expires), kind: "" }
        return { text: name, kind: "" }
    }

    // ── Network interfaces (Advanced) ─────────────────────────────────────────
    // Kept in a ListModel while the page is open, so that typing in a field
    // does not rebuild the rows; every change is copied into eveConfig.

    ListModel { id: ifaceModel }

    function loadInterfaces() {
        ifaceModel.clear()
        var list = root.cfg.interfaces || []
        for (var i = 0; i < list.length; i++) {
            var f = list[i]
            var vlans = []
            var given = f.vlans || []
            for (var j = 0; j < given.length; j++) {
                var v = given[j]
                vlans.push({ tag: "" + (v.tag || ""), mode: v.mode || "dhcp", isMgmt: !!v.isMgmt,
                             ip: v.ip || "", gateway: v.gateway || "", dns: v.dns || "" })
            }
            ifaceModel.append({ ifName: f.ifName || "", mode: f.mode || "dhcp", isMgmt: f.isMgmt !== false,
                                ip: f.ip || "", gateway: f.gateway || "", dns: f.dns || "", ntp: f.ntp || "",
                                vlans: vlans })
        }
    }

    function syncInterfaces() {
        var list = []
        for (var i = 0; i < ifaceModel.count; i++) {
            var f = ifaceModel.get(i)
            var vlans = []
            for (var j = 0; j < f.vlans.count; j++) {
                var v = f.vlans.get(j)
                vlans.push({ tag: v.tag, mode: v.mode, isMgmt: v.isMgmt, ip: v.ip, gateway: v.gateway, dns: v.dns })
            }
            list.push({ ifName: f.ifName, mode: f.mode, isMgmt: f.isMgmt, ip: f.ip, gateway: f.gateway,
                        dns: f.dns, ntp: f.ntp, vlans: vlans })
        }
        root.setCfg("interfaces", list)
    }

    function setIface(index, key, value) {
        if (ifaceModel.get(index)[key] === value)
            return
        ifaceModel.setProperty(index, key, value)
        root.syncInterfaces()
    }

    function setVlan(index, vlanIndex, key, value) {
        var vlans = ifaceModel.get(index).vlans
        if (vlans.get(vlanIndex)[key] === value)
            return
        vlans.setProperty(vlanIndex, key, value)
        root.syncInterfaces()
    }

    function addInterface() {
        // The first free ethN
        var used = []
        for (var i = 0; i < ifaceModel.count; i++)
            used.push(ifaceModel.get(i).ifName)
        var n = 0
        while (used.indexOf("eth" + n) >= 0)
            n++
        ifaceModel.append({ ifName: "eth" + n, mode: "dhcp", isMgmt: true, ip: "", gateway: "", dns: "", ntp: "", vlans: [] })
        root.syncInterfaces()
    }

    // ── One-line summaries for closed sections ────────────────────────────────

    function countSet(values) {
        var n = 0
        for (var i = 0; i < values.length; i++)
            if (values[i]) n++
        return n
    }

    function badge(n) {
        return n > 0 ? (n === 1 ? qsTr("Set") : qsTr("%1 set").arg(n)) : ""
    }

    function interfacesSummary() {
        var parts = []
        var list = root.cfg.interfaces || []
        for (var i = 0; i < list.length; i++) {
            if (list[i].ifName)
                parts.push(list[i].ifName + " " + (list[i].mode === "static" ? (list[i].ip || qsTr("static")) : qsTr("DHCP")))
        }
        return parts.length > 0 ? parts.join(" · ") : qsTr("EVE-OS default: DHCP on the wired ports")
    }

    function proxySummary() {
        if (!root.cfg.proxyEnabled)
            return qsTr("No proxy")
        var parts = []
        if (root.cfg.proxyAddress) parts.push(root.cfg.proxyAddress)
        else if (root.cfg.proxyPacFilePath || root.cfg.proxyPacUrl) parts.push(qsTr("PAC"))
        if (root.cfg.proxyInspects && root.cfg.proxyCertPaths.length > 0)
            parts.push(root.cfg.proxyCertPaths.length === 1 ? qsTr("CA certificate")
                                                            : qsTr("%1 CA certificates").arg(root.cfg.proxyCertPaths.length))
        return parts.length > 0 ? parts.join(" · ") : qsTr("On, not filled in")
    }

    function installationSummary() {
        var parts = []
        if (root.cfg.installDisk) parts.push(qsTr("Install on %1").arg(root.cfg.installDisk))
        if (root.cfg.persistDisk) parts.push(qsTr("data on %1").arg(root.cfg.persistDisk))
        if (root.cfg.nukeDisks) parts.push(qsTr("wipe %1").arg(root.cfg.nukeDisks))
        if (root.cfg.softSerial) parts.push(qsTr("serial %1").arg(root.cfg.softSerial))
        if (root.cfg.console === "serial") parts.push(qsTr("serial console"))
        if (root.cfg.console === "vga") parts.push(qsTr("screen console"))
        if (root.cfg.rebootAfterInstall) parts.push(qsTr("reboot when done"))
        return parts.length > 0 ? parts.join(" · ") : qsTr("Installer defaults")
    }

    // ── Shared pieces ─────────────────────────────────────────────────────────

    component Field: ColumnLayout {
        id: fieldRoot
        property string label: ""
        property string hint: ""
        default property alias control: slot.data
        Layout.fillWidth: true
        // Fields that share a row get equal widths (a row shares its width by
        // preferred width); a field can set another value to take more or less
        Layout.preferredWidth: 100
        spacing: Style.scaled(6)

        Text {
            text: fieldRoot.label
            visible: text.length > 0
            font.family: Style.fontFamily
            font.pointSize: Style.fontSizeDescription
            font.weight: Style.fontWeightMedium
            color: fieldRoot.enabled ? Style.text : Style.disabledText
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
        ColumnLayout {
            id: slot
            Layout.fillWidth: true
            spacing: 0
        }
        Text {
            text: fieldRoot.hint
            visible: text.length > 0
            font.family: Style.fontFamily
            font.pointSize: Style.fontSizeCaption
            color: Style.muted
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

    component CardTitle: RowLayout {
        id: cardTitle
        property alias text: titleLabel.text
        property string hint: ""
        Layout.fillWidth: true
        spacing: Style.spacingSmall
        Text {
            id: titleLabel
            font.family: Style.fontFamily
            font.pointSize: Style.fontSizeFormLabel
            font.weight: Style.fontWeightSemiBold
            color: Style.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Text {
            text: cardTitle.hint
            Layout.fillWidth: true
            font.family: Style.fontFamily
            font.pointSize: Style.fontSizeDescription
            color: Style.muted
            elide: Text.ElideRight
        }
    }

    // The controller address, with the known clusters to pick from
    component ControllerField: Field {
        label: qsTr("Controller address")
        hint: root.wizardContainer.useLocalImage && !root.cfg.controllerUrl
              ? qsTr("Empty: the controller that is set in the image file stays as it is.")
              : qsTr("Pick a known cluster or type any host name.")
        ImSuggestField {
            Layout.fillWidth: true
            suggestions: root.wizardContainer.eveKnownControllers
            placeholderText: root.wizardContainer.useLocalImage ? qsTr("As set in the image") : qsTr("e.g. zedcloud.zededa.net")
            accessibleName: qsTr("Controller address")
            text: root.cfg.controllerUrl
            onTextChanged: {
                if (text !== root.cfg.controllerUrl) {
                    root.wizardContainer.eveControllerTouched = true
                    root.setCfg("controllerUrl", text)
                }
            }
        }
    }

    component WifiFields: RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacingMedium
        Field {
            label: qsTr("Network name")
            ImTextField {
                Layout.fillWidth: true
                placeholderText: qsTr("SSID")
                inputMethodHints: Qt.ImhNoPredictiveText
                Accessible.name: qsTr("WiFi network name")
                text: root.cfg.wifiSsid
                onTextChanged: if (text !== root.cfg.wifiSsid) root.setCfg("wifiSsid", text)
            }
        }
        Field {
            label: qsTr("Password")
            ImTextField {
                Layout.fillWidth: true
                placeholderText: qsTr("WPA2 passphrase")
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
                Accessible.name: qsTr("WiFi password")
                text: root.cfg.wifiPassword
                onTextChanged: if (text !== root.cfg.wifiPassword) root.setCfg("wifiPassword", text)
            }
        }
    }

    // The proxy on/off line used by both views
    component ProxySwitchRow: RowLayout {
        id: proxySwitchRow
        property bool large: false
        Layout.fillWidth: true
        spacing: Style.spacingSmallPlus
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.spacingXXSmall
            Text {
                text: proxySwitchRow.large ? qsTr("My network uses a proxy") : qsTr("Use a proxy")
                font.family: Style.fontFamily
                font.pointSize: Style.fontSizeFormLabel
                font.weight: proxySwitchRow.large ? Style.fontWeightSemiBold : Font.Normal
                color: Style.text
                Layout.fillWidth: true
            }
            Text {
                visible: proxySwitchRow.large
                text: qsTr("Turn on if devices at this site reach the internet through a proxy server.")
                font.family: Style.fontFamily
                font.pointSize: Style.fontSizeDescription
                color: Style.muted
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
        ImSwitch {
            accessibleName: qsTr("My network uses a proxy")
            checked: root.cfg.proxyEnabled
            onToggled: root.setCfg("proxyEnabled", checked)
        }
    }

    component ProxyAddressField: Field {
        label: qsTr("Proxy address")
        hint: qsTr("Host name and port of the proxy.")
        ImTextField {
            Layout.fillWidth: true
            placeholderText: qsTr("e.g. proxy.example.com:3128")
            font.family: Style.fontFamilyMono
            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhUrlCharactersOnly
            Accessible.name: qsTr("Proxy address")
            text: root.cfg.proxyAddress
            onTextChanged: if (text !== root.cfg.proxyAddress) root.setCfg("proxyAddress", text)
        }
    }

    // "The proxy inspects encrypted traffic" and its certificates
    component ProxyInspection: ColumnLayout {
        id: proxyInspection
        property bool allowSeveral: false
        Layout.fillWidth: true
        spacing: Style.spacingSmall

        ImCheckBox {
            Layout.fillWidth: true
            text: qsTr("The proxy inspects encrypted traffic")
            checked: root.cfg.proxyInspects
            onToggled: root.setCfg("proxyInspects", checked)
        }
        Text {
            visible: root.cfg.proxyInspects
            text: qsTr("The device then has to trust the proxy's certificate. Ask your network team for the proxy CA certificate (a .pem or .crt file).")
            font.family: Style.fontFamily
            font.pointSize: Style.fontSizeDescription
            color: Style.muted
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Repeater {
            model: root.cfg.proxyInspects ? root.cfg.proxyCertPaths : []
            ImFileRow {
                id: certRow
                required property string modelData
                required property int index
                readonly property var info: root.certDetail(modelData)
                Layout.fillWidth: true
                label: index === 0 ? qsTr("Proxy CA certificate") : ""
                path: modelData
                detail: info.text
                detailKind: info.kind
                onCleared: {
                    var list = root.cfg.proxyCertPaths.slice()
                    list.splice(certRow.index, 1)
                    root.setCfg("proxyCertPaths", list)
                }
            }
        }

        ImFileRow {
            id: addCertRow
            visible: root.cfg.proxyInspects && (root.cfg.proxyCertPaths.length === 0 || proxyInspection.allowSeveral)
            Layout.fillWidth: true
            label: root.cfg.proxyCertPaths.length === 0 ? qsTr("Proxy CA certificate") : qsTr("Another certificate")
            onChooseRequested: root.pickFile(qsTr("Choose the proxy CA certificate"), root.certFilter, function(path) {
                var list = root.cfg.proxyCertPaths.slice()
                if (list.indexOf(path) < 0)
                    list.push(path)
                root.setCfg("proxyCertPaths", list)
            })
        }
    }

    // ── The Simple / Advanced switch, next to the title ───────────────────────

    headerAccessory: [
        ImSegmented {
            accessibleName: qsTr("Level of detail")
            options: [ { value: "simple", label: qsTr("Simple") }, { value: "advanced", label: qsTr("Advanced") } ]
            value: root.wizardContainer.eveConfigMode
            onSelected: function(value) { root.wizardContainer.setEveConfigMode(value) }
        }
    ]

    // ── Content ───────────────────────────────────────────────────────────────

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

                ImBanner {
                    Layout.fillWidth: true
                    visible: root.configError.length > 0
                    kind: "err"
                    text: root.configError
                    Accessible.role: Accessible.AlertMessage
                }

                Loader {
                    Layout.fillWidth: true
                    sourceComponent: root.advanced ? advancedView : simpleView
                }

                Item { implicitHeight: Style.spacingXSmall }
            }
        }
    ]

    // ── Simple ────────────────────────────────────────────────────────────────

    Component {
        id: simpleView

        ColumnLayout {
            spacing: Style.spacingSmallPlus

            // Settings from Advanced that this view does not show
            ImBanner {
                readonly property var names: root.wizardContainer.eveAdvancedSettings()
                Layout.fillWidth: true
                visible: names.length > 0
                kind: "neutral"
                textFormat: Text.StyledText
                text: (names.length === 1 ? qsTr("<b>1 advanced setting is active</b> (%1). It stays in effect.").arg(names[0])
                                          : qsTr("<b>%1 advanced settings are active</b> (%2). They stay in effect.").arg(names.length).arg(names.join(", ")))
                      + " <a href=\"advanced\">" + qsTr("Show in Advanced") + "</a>"
                onLinkActivated: root.wizardContainer.setEveConfigMode("advanced")
            }

            ImCard {
                Layout.fillWidth: true
                spacing: Style.spacingSmall
                CardTitle { text: qsTr("Controller") }
                ControllerField {}
            }

            ImCard {
                Layout.fillWidth: true
                spacing: Style.spacingSmall
                enabled: !root.bootstrapActive
                opacity: enabled ? 1.0 : 0.55
                CardTitle { text: qsTr("WiFi"); hint: qsTr("Leave empty to use a network cable") }
                WifiFields {}
            }

            ImCard {
                Layout.fillWidth: true
                spacing: Style.spacingSmallPlus
                enabled: !root.bootstrapActive
                opacity: enabled ? 1.0 : 0.55
                ProxySwitchRow { large: true }
                ProxyAddressField { visible: root.cfg.proxyEnabled }
                ProxyInspection { visible: root.cfg.proxyEnabled }
            }
        }
    }

    // ── Advanced ──────────────────────────────────────────────────────────────

    Component {
        id: advancedView

        ColumnLayout {
            spacing: Style.spacingTiny

            ImSection {
                Layout.fillWidth: true
                title: qsTr("Controller")
                summary: root.cfg.controllerUrl || (root.wizardContainer.useLocalImage ? qsTr("As set in the image") : qsTr("Not set"))
                badge: root.badge(root.countSet([root.cfg.rootCertPath, root.cfg.onboardCertPath]))

                ControllerField {}
                ImFileRow {
                    readonly property var info: root.certDetail(root.cfg.rootCertPath)
                    Layout.fillWidth: true
                    label: qsTr("Controller root certificate")
                    emptyText: qsTr("Only for controllers signed by a private CA")
                    path: root.cfg.rootCertPath
                    detail: info.text
                    detailKind: info.kind
                    onChooseRequested: root.pickFile(qsTr("Choose the controller root certificate"), root.certFilter,
                                                     function(path) { root.setCfg("rootCertPath", path) })
                    onCleared: root.setCfg("rootCertPath", "")
                }
                ImFileRow {
                    readonly property var info: root.certDetail(root.cfg.onboardCertPath)
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    label: qsTr("Onboarding certificate")
                    emptyText: qsTr("Default from the image")
                    path: root.cfg.onboardCertPath
                    detail: info.text
                    detailKind: info.kind
                    onChooseRequested: root.pickFile(qsTr("Choose the onboarding certificate"), root.certFilter,
                                                     function(path) { root.setCfg("onboardCertPath", path) })
                    onCleared: root.setCfg("onboardCertPath", "")
                }
                ImFileRow {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    label: qsTr("Onboarding key")
                    emptyText: qsTr("Default from the image")
                    path: root.cfg.onboardKeyPath
                    onChooseRequested: root.pickFile(qsTr("Choose the onboarding key"),
                                                     qsTr("Keys (*.pem *.key);;All files (*)"),
                                                     function(path) { root.setCfg("onboardKeyPath", path) })
                    onCleared: root.setCfg("onboardKeyPath", "")
                }
            }

            ImSection {
                Layout.fillWidth: true
                enabled: !root.bootstrapActive
                title: qsTr("Network interfaces")
                summary: root.bootstrapActive ? qsTr("From the bootstrap config") : root.interfacesSummary()
                badge: root.bootstrapActive ? "" : root.badge(ifaceModel.count)

                Text {
                    visible: ifaceModel.count === 0
                    text: qsTr("No interface is listed, so EVE-OS uses its default: DHCP on the wired ports. Add one to set a static address, NTP servers or VLANs.")
                    font.family: Style.fontFamily
                    font.pointSize: Style.fontSizeDescription
                    color: Style.muted
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Text {
                    visible: ifaceModel.count > 0
                    text: qsTr("EVE-OS reaches the controller through the ports marked Management.")
                    font.family: Style.fontFamily
                    font.pointSize: Style.fontSizeDescription
                    color: Style.muted
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Repeater {
                    model: ifaceModel

                    Rectangle {
                        id: ifaceCard
                        required property int index
                        required property string ifName
                        required property string mode
                        required property bool isMgmt
                        required property string ip
                        required property string gateway
                        required property string dns
                        required property string ntp
                        required property var vlans

                        Layout.fillWidth: true
                        implicitHeight: ifaceColumn.implicitHeight + Style.spacingSmallPlus * 2
                        radius: Style.sidebarItemBorderRadius
                        color: Style.bg
                        border.width: 1
                        border.color: Style.border

                        ColumnLayout {
                            id: ifaceColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Style.spacingSmallPlus
                            spacing: Style.spacingSmall

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.spacingSmallPlus

                                Field {
                                    label: qsTr("Interface")
                                    Layout.fillWidth: false
                                    Layout.preferredWidth: Style.scaled(110)
                                    ImTextField {
                                        Layout.fillWidth: true
                                        font.family: Style.fontFamilyMono
                                        placeholderText: "eth0"
                                        inputMethodHints: Qt.ImhNoPredictiveText
                                        Accessible.name: qsTr("Interface name")
                                        text: ifaceCard.ifName
                                        onTextChanged: root.setIface(ifaceCard.index, "ifName", text)
                                    }
                                }
                                Field {
                                    label: qsTr("Addressing")
                                    Layout.fillWidth: false
                                    Layout.preferredWidth: Style.scaled(130)
                                    ImComboBox {
                                        Layout.fillWidth: true
                                        model: [qsTr("DHCP"), qsTr("Static")]
                                        currentIndex: ifaceCard.mode === "static" ? 1 : 0
                                        Accessible.name: qsTr("Addressing of %1").arg(ifaceCard.ifName)
                                        onActivated: function(i) { root.setIface(ifaceCard.index, "mode", i === 1 ? "static" : "dhcp") }
                                    }
                                }
                                ImCheckBox {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignBottom
                                    Layout.preferredHeight: Style.scaled(40)
                                    text: qsTr("Management")
                                    checked: ifaceCard.isMgmt
                                    onToggled: root.setIface(ifaceCard.index, "isMgmt", checked)
                                }
                                ImIconButton {
                                    Layout.alignment: Qt.AlignBottom
                                    implicitWidth: Style.scaled(40)
                                    implicitHeight: Style.scaled(40)
                                    iconName: "trash"
                                    label: qsTr("Remove %1").arg(ifaceCard.ifName)
                                    onClicked: {
                                        ifaceModel.remove(ifaceCard.index)
                                        root.syncInterfaces()
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.spacingSmallPlus
                                visible: ifaceCard.mode === "static"

                                Field {
                                    label: qsTr("IP address / prefix")
                                    ImTextField {
                                        Layout.fillWidth: true
                                        font.family: Style.fontFamilyMono
                                        placeholderText: "192.168.1.100/24"
                                        Accessible.name: qsTr("IP address of %1").arg(ifaceCard.ifName)
                                        text: ifaceCard.ip
                                        onTextChanged: root.setIface(ifaceCard.index, "ip", text)
                                    }
                                }
                                Field {
                                    label: qsTr("Gateway")
                                    ImTextField {
                                        Layout.fillWidth: true
                                        font.family: Style.fontFamilyMono
                                        placeholderText: "192.168.1.1"
                                        Accessible.name: qsTr("Gateway of %1").arg(ifaceCard.ifName)
                                        text: ifaceCard.gateway
                                        onTextChanged: root.setIface(ifaceCard.index, "gateway", text)
                                    }
                                }
                                Field {
                                    label: qsTr("DNS servers")
                                    ImTextField {
                                        Layout.fillWidth: true
                                        font.family: Style.fontFamilyMono
                                        placeholderText: "192.168.1.1, 8.8.8.8"
                                        Accessible.name: qsTr("DNS servers of %1").arg(ifaceCard.ifName)
                                        text: ifaceCard.dns
                                        onTextChanged: root.setIface(ifaceCard.index, "dns", text)
                                    }
                                }
                            }

                            Field {
                                label: qsTr("NTP servers")
                                hint: qsTr("Comma-separated. Empty: the servers from DHCP, or the EVE-OS default.")
                                ImTextField {
                                    Layout.fillWidth: true
                                    placeholderText: qsTr("e.g. 0.pool.ntp.org, 192.168.1.5")
                                    inputMethodHints: Qt.ImhNoPredictiveText
                                    Accessible.name: qsTr("NTP servers of %1").arg(ifaceCard.ifName)
                                    text: ifaceCard.ntp
                                    onTextChanged: root.setIface(ifaceCard.index, "ntp", text)
                                }
                            }

                            Repeater {
                                model: ifaceCard.vlans

                                ColumnLayout {
                                    id: vlanRow
                                    required property int index
                                    required property string tag
                                    required property string mode
                                    required property bool isMgmt
                                    required property string ip
                                    required property string gateway
                                    required property string dns
                                    Layout.fillWidth: true
                                    spacing: Style.spacingSmall

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Style.spacingSmallPlus
                                        Field {
                                            label: qsTr("VLAN tag")
                                            Layout.fillWidth: false
                                            Layout.preferredWidth: Style.scaled(110)
                                            ImTextField {
                                                Layout.fillWidth: true
                                                font.family: Style.fontFamilyMono
                                                placeholderText: "1–4094"
                                                inputMethodHints: Qt.ImhDigitsOnly
                                                Accessible.name: qsTr("VLAN tag on %1").arg(ifaceCard.ifName)
                                                text: vlanRow.tag
                                                onTextChanged: root.setVlan(ifaceCard.index, vlanRow.index, "tag", text)
                                            }
                                        }
                                        Field {
                                            label: qsTr("Addressing")
                                            Layout.fillWidth: false
                                            Layout.preferredWidth: Style.scaled(130)
                                            ImComboBox {
                                                Layout.fillWidth: true
                                                model: [qsTr("DHCP"), qsTr("Static")]
                                                currentIndex: vlanRow.mode === "static" ? 1 : 0
                                                Accessible.name: qsTr("Addressing of VLAN %1").arg(vlanRow.tag)
                                                onActivated: function(i) { root.setVlan(ifaceCard.index, vlanRow.index, "mode", i === 1 ? "static" : "dhcp") }
                                            }
                                        }
                                        ImCheckBox {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignBottom
                                            Layout.preferredHeight: Style.scaled(40)
                                            text: qsTr("Management")
                                            checked: vlanRow.isMgmt
                                            onToggled: root.setVlan(ifaceCard.index, vlanRow.index, "isMgmt", checked)
                                        }
                                        ImIconButton {
                                            Layout.alignment: Qt.AlignBottom
                                            implicitWidth: Style.scaled(40)
                                            implicitHeight: Style.scaled(40)
                                            iconName: "trash"
                                            label: qsTr("Remove VLAN %1").arg(vlanRow.tag)
                                            onClicked: {
                                                ifaceModel.get(ifaceCard.index).vlans.remove(vlanRow.index)
                                                root.syncInterfaces()
                                            }
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Style.spacingSmallPlus
                                        visible: vlanRow.mode === "static"
                                        Field {
                                            label: qsTr("IP address / prefix")
                                            ImTextField {
                                                Layout.fillWidth: true
                                                font.family: Style.fontFamilyMono
                                                placeholderText: "10.1.20.5/24"
                                                Accessible.name: qsTr("IP address of VLAN %1").arg(vlanRow.tag)
                                                text: vlanRow.ip
                                                onTextChanged: root.setVlan(ifaceCard.index, vlanRow.index, "ip", text)
                                            }
                                        }
                                        Field {
                                            label: qsTr("Gateway")
                                            ImTextField {
                                                Layout.fillWidth: true
                                                font.family: Style.fontFamilyMono
                                                placeholderText: "10.1.20.1"
                                                Accessible.name: qsTr("Gateway of VLAN %1").arg(vlanRow.tag)
                                                text: vlanRow.gateway
                                                onTextChanged: root.setVlan(ifaceCard.index, vlanRow.index, "gateway", text)
                                            }
                                        }
                                        Field {
                                            label: qsTr("DNS servers")
                                            ImTextField {
                                                Layout.fillWidth: true
                                                font.family: Style.fontFamilyMono
                                                placeholderText: "10.1.20.1"
                                                Accessible.name: qsTr("DNS servers of VLAN %1").arg(vlanRow.tag)
                                                text: vlanRow.dns
                                                onTextChanged: root.setVlan(ifaceCard.index, vlanRow.index, "dns", text)
                                            }
                                        }
                                    }
                                }
                            }

                            ImButton {
                                text: qsTr("Add VLAN")
                                accessibleDescription: qsTr("Add a VLAN on %1").arg(ifaceCard.ifName)
                                onClicked: {
                                    ifaceModel.get(ifaceCard.index).vlans.append({ tag: "", mode: "dhcp", isMgmt: false, ip: "", gateway: "", dns: "" })
                                    root.syncInterfaces()
                                }
                            }
                        }
                    }
                }

                ImButton {
                    text: qsTr("Add interface")
                    onClicked: root.addInterface()
                }
            }

            ImSection {
                Layout.fillWidth: true
                enabled: !root.bootstrapActive
                title: qsTr("WiFi")
                summary: root.bootstrapActive ? qsTr("From the bootstrap config") : (root.cfg.wifiSsid || qsTr("Not set"))
                badge: root.bootstrapActive ? "" : root.badge(root.cfg.wifiSsid ? 1 : 0)

                Text {
                    text: qsTr("A WiFi network for EVE-OS to use on first boot. Leave empty to use a network cable.")
                    font.family: Style.fontFamily
                    font.pointSize: Style.fontSizeDescription
                    color: Style.muted
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                WifiFields {}
            }

            ImSection {
                Layout.fillWidth: true
                enabled: !root.bootstrapActive
                title: qsTr("Proxy and certificates")
                summary: root.bootstrapActive ? qsTr("From the bootstrap config") : root.proxySummary()
                badge: root.bootstrapActive || !root.cfg.proxyEnabled ? ""
                       : root.badge(root.countSet([root.cfg.proxyAddress, root.cfg.proxyExceptions,
                                                   root.cfg.proxyPacUrl || root.cfg.proxyPacFilePath,
                                                   root.cfg.proxyInspects && root.cfg.proxyCertPaths.length > 0]))

                ProxySwitchRow {}

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.spacingSmallPlus
                    visible: root.cfg.proxyEnabled

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.spacingMedium
                        ProxyAddressField {
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredWidth: 150
                        }
                        Field {
                            Layout.alignment: Qt.AlignTop
                            label: qsTr("Do not proxy")
                            hint: qsTr("Comma-separated hosts, domains or networks.")
                            ImTextField {
                                Layout.fillWidth: true
                                font.family: Style.fontFamilyMono
                                placeholderText: qsTr("e.g. .corp.example.com")
                                inputMethodHints: Qt.ImhNoPredictiveText
                                Accessible.name: qsTr("Do not proxy")
                                text: root.cfg.proxyExceptions
                                onTextChanged: if (text !== root.cfg.proxyExceptions) root.setCfg("proxyExceptions", text)
                            }
                        }
                    }
                    Field {
                        Layout.alignment: Qt.AlignTop
                        enabled: root.cfg.proxyPacFilePath.length === 0
                        label: qsTr("Auto-config (PAC) URL")
                        hint: qsTr("Use this, or a PAC file, when the proxy is found through a PAC script.")
                        ImTextField {
                            Layout.fillWidth: true
                            placeholderText: qsTr("e.g. http://wpad.example.com/proxy.pac")
                            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhUrlCharactersOnly
                            Accessible.name: qsTr("PAC URL")
                            text: root.cfg.proxyPacUrl
                            onTextChanged: if (text !== root.cfg.proxyPacUrl) root.setCfg("proxyPacUrl", text)
                        }
                    }
                    ImFileRow {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        label: qsTr("PAC file")
                        path: root.cfg.proxyPacFilePath
                        detail: path.length > 0 ? qsTr("Its contents are written to the drive, in place of the URL.") : ""
                        onChooseRequested: root.pickFile(qsTr("Choose the PAC file"), qsTr("PAC files (*.pac *.dat *.js);;All files (*)"),
                                                         function(path) { root.setCfg("proxyPacFilePath", path) })
                        onCleared: root.setCfg("proxyPacFilePath", "")
                    }
                    ProxyInspection { allowSeveral: true }
                }
            }

            ImSection {
                Layout.fillWidth: true
                title: qsTr("Installation")
                enabled: !root.isIso
                summary: root.isIso ? qsTr("Not available for an installer ISO") : root.installationSummary()
                badge: root.isIso ? "" : root.badge(root.countSet([root.cfg.installDisk, root.cfg.persistDisk, root.cfg.nukeDisks,
                                                                   root.cfg.softSerial, root.cfg.console, root.cfg.rebootAfterInstall]))
                onEnabledChanged: if (!enabled) expanded = false

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.spacingMedium
                    Field {
                        Layout.alignment: Qt.AlignTop
                        label: qsTr("Install EVE-OS on")
                        hint: root.cfg.hardware === "fr201-nvme"
                              ? qsTr("Linux disk name. Empty: sdb, the NVMe drive of an OnLogic FR201 without eMMC.")
                              : qsTr("Linux disk name, e.g. nvme0n1. Empty: the first free disk.")
                        ImTextField {
                            Layout.fillWidth: true
                            font.family: Style.fontFamilyMono
                            placeholderText: root.cfg.hardware === "fr201-nvme" ? "sdb" : qsTr("Chosen by the installer")
                            inputMethodHints: Qt.ImhNoPredictiveText
                            Accessible.name: qsTr("Install disk")
                            text: root.cfg.installDisk
                            onTextChanged: if (text !== root.cfg.installDisk) root.setCfg("installDisk", text)
                        }
                    }
                    Field {
                        Layout.alignment: Qt.AlignTop
                        label: qsTr("Store data (/persist) on")
                        hint: qsTr("One disk, or several separated by commas.")
                        ImTextField {
                            Layout.fillWidth: true
                            font.family: Style.fontFamilyMono
                            placeholderText: qsTr("Same disk as EVE-OS")
                            inputMethodHints: Qt.ImhNoPredictiveText
                            Accessible.name: qsTr("Persist disk")
                            text: root.cfg.persistDisk
                            onTextChanged: if (text !== root.cfg.persistDisk) root.setCfg("persistDisk", text)
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.spacingMedium
                    Field {
                        Layout.alignment: Qt.AlignTop
                        label: qsTr("Wipe these disks first")
                        hint: qsTr("Clears their partition tables before installing, e.g. sda, sdb.")
                        ImTextField {
                            Layout.fillWidth: true
                            font.family: Style.fontFamilyMono
                            placeholderText: qsTr("None")
                            inputMethodHints: Qt.ImhNoPredictiveText
                            Accessible.name: qsTr("Disks to wipe")
                            text: root.cfg.nukeDisks
                            onTextChanged: if (text !== root.cfg.nukeDisks) root.setCfg("nukeDisks", text)
                        }
                    }
                    Field {
                        Layout.alignment: Qt.AlignTop
                        label: qsTr("Soft serial number")
                        hint: qsTr("Identifies the device at onboarding in place of the hardware serial.")
                        ImTextField {
                            Layout.fillWidth: true
                            font.family: Style.fontFamilyMono
                            placeholderText: qsTr("Generated by the installer")
                            inputMethodHints: Qt.ImhNoPredictiveText
                            Accessible.name: qsTr("Soft serial number")
                            text: root.cfg.softSerial
                            onTextChanged: if (text !== root.cfg.softSerial) root.setCfg("softSerial", text)
                        }
                    }
                }
                ImBanner {
                    Layout.fillWidth: true
                    visible: root.cfg.nukeDisks.length > 0
                    kind: "warn"
                    text: qsTr("Everything on %1 is erased on the target device when the installer starts.").arg(root.cfg.nukeDisks)
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.spacingMedium
                    Field {
                        Layout.fillWidth: false
                        Layout.preferredWidth: Style.scaled(250)
                        label: qsTr("Console")
                        ImComboBox {
                            Layout.fillWidth: true
                            model: [qsTr("Image default"), qsTr("Screen (VGA)"), qsTr("Serial port (ttyS0)")]
                            currentIndex: root.cfg.console === "vga" ? 1 : root.cfg.console === "serial" ? 2 : 0
                            Accessible.name: qsTr("Console")
                            onActivated: function(i) { root.setCfg("console", i === 1 ? "vga" : i === 2 ? "serial" : "") }
                        }
                    }
                    ImCheckBox {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: Style.scaled(4)
                        text: qsTr("Reboot automatically after installation")
                        checked: root.cfg.rebootAfterInstall
                        onToggled: root.setCfg("rebootAfterInstall", checked)
                    }
                }
            }

            ImSection {
                Layout.fillWidth: true
                title: qsTr("Device access")
                summary: root.cfg.authorizedKeys ? qsTr("SSH key set") : qsTr("Not set")
                badge: root.badge(root.cfg.authorizedKeys ? 1 : 0)

                Field {
                    label: qsTr("SSH public key for the debug console")
                    hint: qsTr("Used only until the controller takes over the device configuration.")
                    ImTextField {
                        Layout.fillWidth: true
                        font.family: Style.fontFamilyMono
                        placeholderText: "ssh-ed25519 AAAA… name@host"
                        inputMethodHints: Qt.ImhNoPredictiveText
                        Accessible.name: qsTr("SSH public key")
                        text: root.cfg.authorizedKeys
                        onTextChanged: if (text !== root.cfg.authorizedKeys) root.setCfg("authorizedKeys", text)
                    }
                }
            }

            ImSection {
                Layout.fillWidth: true
                title: qsTr("Bootstrap config")
                summary: root.bootstrapActive ? root.cfg.bootstrapConfigPath.split(/[\\/]/).pop() : qsTr("Not set")
                badge: root.badge(root.bootstrapActive ? 1 : 0)

                Text {
                    text: qsTr("A bootstrap config is a file exported from the controller for one device. When one is chosen, the network settings come from that file, and the Network interfaces, WiFi and Proxy sections are switched off.")
                    font.family: Style.fontFamily
                    font.pointSize: Style.fontSizeDescription
                    color: Style.muted
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                ImFileRow {
                    Layout.fillWidth: true
                    label: qsTr("Bootstrap config file (bootstrap-config.pb)")
                    path: root.cfg.bootstrapConfigPath
                    onChooseRequested: root.pickFile(qsTr("Choose the bootstrap config"),
                                                     qsTr("Bootstrap config (*.pb);;All files (*)"),
                                                     function(path) { root.setCfg("bootstrapConfigPath", path) })
                    onCleared: root.setCfg("bootstrapConfigPath", "")
                }
            }
        }
    }

    // Used where the system's own file chooser is not available
    ImFileDialog {
        id: fallbackDialog
        property var picked: null
        parent: Overlay.overlay
        anchors.centerIn: parent
        onAccepted: {
            if (picked)
                picked(root.urlToPath(selectedFile))
            picked = null
        }
    }

    Component.onCompleted: {
        // A downloaded release goes to the production cluster unless told
        // otherwise; a local image file keeps the controller it was built for.
        if (!root.wizardContainer.eveControllerTouched) {
            var wanted = root.wizardContainer.useLocalImage ? "" : root.wizardContainer.eveKnownControllers[0]
            if (root.cfg.controllerUrl !== wanted)
                root.setCfg("controllerUrl", wanted)
        }
        root.loadInterfaces()
    }
}
