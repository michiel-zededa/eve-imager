/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 ZEDEDA, Inc.
 *
 * One file to choose: a label, then either "no file" with a Choose button,
 * or the chosen file's name with a button to take it away again. A line of
 * detail under it can say what the file holds, or what is wrong with it.
 */

import QtQuick
import QtQuick.Layouts

import RpiImager

ColumnLayout {
    id: root

    property string label: ""
    /** Full path of the chosen file, "" if none. */
    property string path: ""
    property string emptyText: qsTr("No file chosen")
    property string detail: ""
    /** "" (plain) | "err" | "warn" */
    property string detailKind: ""
    signal chooseRequested()
    signal cleared()

    readonly property string fileName: path.length > 0 ? path.split(/[\\/]/).pop() : ""
    property alias chooseButton: chooseButton

    spacing: Style.scaled(6)

    Text {
        visible: root.label.length > 0
        text: root.label
        font.family: Style.fontFamily
        font.pointSize: Style.fontSizeDescription
        font.weight: Style.fontWeightMedium
        color: root.enabled ? Style.text : Style.disabledText
        Layout.fillWidth: true
        elide: Text.ElideRight
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacingSmall

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Style.scaled(40)
            radius: Style.controlBorderRadius
            color: root.path.length > 0 ? Style.surface : Style.surface2
            border.width: 1
            border.color: root.detailKind === "err" && root.path.length > 0 ? Style.errBorder : Style.border

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.scaled(12)
                anchors.rightMargin: Style.scaled(4)
                spacing: Style.spacingTiny

                ImIcon {
                    visible: root.path.length > 0
                    name: "file"
                    size: Style.scaled(16)
                    color: root.detailKind === "err" ? Style.err : Style.accentText
                }
                Text {
                    Layout.fillWidth: true
                    text: root.path.length > 0 ? root.fileName : root.emptyText
                    font.family: root.path.length > 0 ? Style.fontFamilyMono : Style.fontFamily
                    font.pointSize: Style.fontSizeDescription
                    color: root.path.length > 0 && root.enabled ? Style.text : Style.disabledText
                    elide: Text.ElideMiddle
                }
                ImIconButton {
                    visible: root.path.length > 0
                    implicitWidth: Style.scaled(32)
                    implicitHeight: Style.scaled(32)
                    iconName: "x"
                    label: qsTr("Remove %1").arg(root.fileName)
                    onClicked: root.cleared()
                }
            }
        }

        ImButton {
            id: chooseButton
            visible: root.path.length === 0
            text: qsTr("Choose file…")
            accessibleDescription: root.label
            onClicked: root.chooseRequested()
        }
    }

    Text {
        visible: root.detail.length > 0
        text: root.detail
        font.family: Style.fontFamily
        font.pointSize: Style.fontSizeCaption
        color: root.detailKind === "err" ? Style.err
             : root.detailKind === "warn" ? Style.warn : Style.muted
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
}
