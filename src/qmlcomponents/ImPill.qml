/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 ZEDEDA, Inc.
 *
 * A status pill: short text on a tinted, fully rounded background.
 * kind: "ok" | "warn" | "err" | "info" | "neutral" | "plain"
 */

import QtQuick

import RpiImager

Rectangle {
    id: root

    property string text: ""
    property string kind: "neutral"
    /** Optional ImIcon name shown before the text. */
    property string iconName: ""

    readonly property color fg: kind === "ok" ? Style.ok
                              : kind === "warn" ? Style.warn
                              : kind === "err" ? Style.err
                              : kind === "info" ? Style.info
                              : kind === "plain" ? Style.muted
                              : Style.neutral
    readonly property color fill: kind === "ok" ? Style.okBg
                                : kind === "warn" ? Style.warnBg
                                : kind === "err" ? Style.errBg
                                : kind === "info" ? Style.infoBg
                                : kind === "plain" ? Style.surface2
                                : Style.neutralBg
    readonly property color line: kind === "ok" ? Style.okBorder
                                : kind === "warn" ? Style.warnBorder
                                : kind === "err" ? Style.errBorder
                                : kind === "info" ? Style.infoBorder
                                : kind === "plain" ? Style.border
                                : Style.neutralBorder

    color: fill
    border.color: line
    border.width: 1
    radius: height / 2

    implicitHeight: Math.max(Style.scaled(24), row.implicitHeight + Style.scaled(6))
    implicitWidth: row.implicitWidth + Style.scaled(22)

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Style.scaled(6)

        ImIcon {
            visible: root.iconName.length > 0
            name: root.iconName
            color: root.fg
            size: Style.scaled(14)
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: root.text
            color: root.fg
            font.family: Style.fontFamily
            font.pointSize: Style.fontSizeCaption
            font.weight: Style.fontWeightMedium
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Accessible.role: Accessible.StaticText
    Accessible.name: root.text
}
