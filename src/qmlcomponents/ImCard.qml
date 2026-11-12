/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 ZEDEDA, Inc.
 *
 * A white (or dark-surface) panel with a thin border and rounded corners:
 * the basic container of the ZEDEDA product style. Children are laid out in
 * a column; set `padding` to 0 for content that runs edge to edge (lists,
 * rows with their own dividers).
 */

import QtQuick
import QtQuick.Layouts

import RpiImager

Rectangle {
    id: root

    default property alias content: column.data
    property real padding: Style.cardPadding
    property alias spacing: column.spacing

    color: Style.surface
    border.color: Style.border
    border.width: 1
    radius: Style.sectionBorderRadius

    implicitWidth: column.implicitWidth + 2 * padding
    implicitHeight: column.implicitHeight + 2 * padding

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: Style.spacingMedium
    }
}
