/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 ZEDEDA, Inc.
 *
 * A full-width message with a status tint: icon, text, optional busy spinner.
 * kind: "info" | "warn" | "err" | "ok" | "neutral"
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import RpiImager

Rectangle {
    id: root

    property string text: ""
    property string kind: "info"
    property bool busy: false
    /** Set to "" to hide the icon. Defaults to one that fits the kind. */
    property string iconName: kind === "warn" || kind === "err" ? "alert"
                            : kind === "ok" ? "check-circle" : "info"
    property alias textFormat: label.textFormat
    signal linkActivated(string link)

    readonly property color fg: kind === "ok" ? Style.ok
                              : kind === "warn" ? Style.warn
                              : kind === "err" ? Style.err
                              : kind === "neutral" ? Style.neutral
                              : Style.info
    readonly property color fill: kind === "ok" ? Style.okBg
                                : kind === "warn" ? Style.warnBg
                                : kind === "err" ? Style.errBg
                                : kind === "neutral" ? Style.neutralBg
                                : Style.infoBg
    readonly property color line: kind === "ok" ? Style.okBorder
                                : kind === "warn" ? Style.warnBorder
                                : kind === "err" ? Style.errBorder
                                : kind === "neutral" ? Style.neutralBorder
                                : Style.infoBorder

    color: fill
    border.color: line
    border.width: 1
    radius: Style.controlBorderRadius

    implicitHeight: row.implicitHeight + Style.scaled(20)
    implicitWidth: row.implicitWidth + Style.scaled(28)

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.scaled(14)
        anchors.rightMargin: Style.scaled(14)
        spacing: Style.scaled(10)

        BusyIndicator {
            visible: root.busy
            running: root.busy
            implicitWidth: Style.scaled(20)
            implicitHeight: Style.scaled(20)
            Layout.alignment: Qt.AlignTop
        }
        ImIcon {
            visible: !root.busy && root.iconName.length > 0
            name: root.iconName
            color: root.fg
            size: Style.scaled(18)
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: Style.scaled(1)
        }
        Text {
            id: label
            Layout.fillWidth: true
            text: root.text
            color: root.fg
            linkColor: root.fg
            font.family: Style.fontFamily
            font.pointSize: Style.fontSizeDescription
            wrapMode: Text.WordWrap
            onLinkActivated: function(link) { root.linkActivated(link) }
        }
    }

    Accessible.role: Accessible.StaticText
    Accessible.name: root.text
}
