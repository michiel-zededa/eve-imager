/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 ZEDEDA, Inc.
 *
 * A card that opens and closes. Closed, its header says in one line what is
 * set inside; open, the contents follow under a hairline.
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T

import RpiImager

Rectangle {
    id: root

    property string title: ""
    /** One line shown at the right of the header while closed. */
    property string summary: ""
    /** Short text for a pill in the header, e.g. "2 set"; "" for none. */
    property string badge: ""
    property bool expanded: false
    default property alias content: body.data
    property alias header: header

    color: Style.surface
    border.color: Style.border
    border.width: 1
    radius: expanded ? Style.sectionBorderRadius : Style.sidebarItemBorderRadius
    implicitHeight: header.height + (expanded ? divider.height + body.implicitHeight + Style.spacingSmallPlus + Style.cardPadding : 0)
    implicitWidth: Style.scaled(300)
    opacity: enabled ? 1.0 : 0.55

    T.AbstractButton {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Style.scaled(50)
        activeFocusOnTab: true
        focusPolicy: Qt.TabFocus
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        Keys.onSpacePressed: clicked()

        background: Rectangle {
            radius: root.radius
            color: header.hovered && !root.expanded ? Style.surface2 : "transparent"
            border.width: header.activeFocus ? 2 : 0
            border.color: Style.accent
        }

        leftPadding: Style.scaled(14)
        rightPadding: Style.scaled(16)

        contentItem: RowLayout {
            spacing: Style.spacingSmall

            ImIcon {
                name: "chevron-down"
                size: Style.scaled(18)
                color: Style.muted
                rotation: root.expanded ? 0 : -90
                Behavior on rotation { NumberAnimation { duration: 120 } }
            }
            Text {
                text: root.title
                font.family: Style.fontFamily
                font.pointSize: Style.fontSizeFormLabel
                font.weight: Style.fontWeightSemiBold
                color: Style.text
            }
            Text {
                Layout.fillWidth: true
                text: root.expanded ? "" : root.summary
                font.family: Style.fontFamily
                font.pointSize: Style.fontSizeDescription
                color: Style.muted
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
            ImPill {
                visible: root.badge.length > 0
                text: root.badge
                kind: "neutral"
            }
        }

        Accessible.role: Accessible.Button
        Accessible.name: root.title + (root.summary.length > 0 ? ", " + root.summary : "")
                         + (root.expanded ? qsTr(", open") : qsTr(", closed"))
        Accessible.onPressAction: clicked()
    }

    Rectangle {
        id: divider
        visible: root.expanded
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        height: 1
        color: Style.border
    }

    ColumnLayout {
        id: body
        visible: root.expanded
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: divider.bottom
        anchors.leftMargin: Style.cardPadding
        anchors.rightMargin: Style.cardPadding
        anchors.topMargin: Style.spacingSmallPlus
        spacing: Style.spacingSmallPlus
    }
}
