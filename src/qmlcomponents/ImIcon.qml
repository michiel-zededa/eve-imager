/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 ZEDEDA, Inc.
 *
 * A small set of line icons, drawn as vector paths so that they can take any
 * theme colour (Qt's SVG image loader cannot recolour a file). Icon geometry:
 * Lucide (https://lucide.dev), ISC License, 24x24 grid, 2px round strokes.
 */

import QtQuick
import QtQuick.Shapes

import RpiImager

Item {
    id: root

    /** One of the keys of `paths` below. */
    property string name: ""
    property color color: Style.text
    /** Edge length in pixels; the 24x24 design grid is scaled to it. */
    property real size: 20
    property real strokeWidth: 2

    implicitWidth: size
    implicitHeight: size

    readonly property var paths: ({
        "layers":      "M12 2 L21 7 L12 12 L3 7 Z M3 12 L12 17 L21 12 M3 17 L12 22 L21 17",
        "drive":       "M22 12 H2 M5.45 5.11 L2 12 v6 a2 2 0 0 0 2 2 h16 a2 2 0 0 0 2 -2 v-6 l-3.45 -6.89 A2 2 0 0 0 16.76 4 H7.24 a2 2 0 0 0 -1.79 1.11 Z M6 16 h.01 M10 16 h.01",
        "sliders":     "M21 4 h-7 M10 4 H3 M21 12 h-9 M8 12 H3 M21 20 h-5 M12 20 H3 M14 2 v4 M8 10 v4 M16 18 v4",
        "download":    "M21 15 v4 a2 2 0 0 1 -2 2 H5 a2 2 0 0 1 -2 -2 v-4 M7 10 l5 5 l5 -5 M12 15 V3",
        "check":       "M20 6 L9 17 l-5 -5",
        "check-circle":"M22 12 A10 10 0 1 1 2 12 A10 10 0 1 1 22 12 Z M9 12 l2 2 l4 -4",
        "chevron-down":"M6 9 l6 6 l6 -6",
        "monitor":     "M4 3 h16 a2 2 0 0 1 2 2 v10 a2 2 0 0 1 -2 2 H4 a2 2 0 0 1 -2 -2 V5 a2 2 0 0 1 2 -2 Z M8 21 h8 M12 17 v4",
        "sun":         "M16 12 A4 4 0 1 1 8 12 A4 4 0 1 1 16 12 Z M12 2 v2 M12 20 v2 M4.93 4.93 l1.41 1.41 M17.66 17.66 l1.41 1.41 M2 12 h2 M20 12 h2 M6.34 17.66 l-1.41 1.41 M19.07 4.93 l-1.41 1.41",
        "moon":        "M12 3 a6 6 0 0 0 9 9 a9 9 0 1 1 -9 -9 Z",
        "info":        "M22 12 A10 10 0 1 1 2 12 A10 10 0 1 1 22 12 Z M12 16 v-4 M12 8 h.01",
        "alert":       "M21.73 18 l-8 -14 a2 2 0 0 0 -3.48 0 l-8 14 A2 2 0 0 0 4 21 h16 a2 2 0 0 0 1.73 -3 Z M12 9 v4 M12 17 h.01",
        "file":        "M15 2 H6 a2 2 0 0 0 -2 2 v16 a2 2 0 0 0 2 2 h12 a2 2 0 0 0 2 -2 V7 Z M14 2 v4 a2 2 0 0 0 2 2 h4",
        "x":           "M18 6 L6 18 M6 6 l12 12",
        "usb":         "M11 7 A1 1 0 1 1 9 7 A1 1 0 1 1 11 7 Z M5 20 A1 1 0 1 1 3 20 A1 1 0 1 1 5 20 Z M4.7 19.3 L19 5 M21 3 l-3 1 l2 2 Z M9.26 7.68 L5 12 l2 5 M10 14 l5 2 l3.5 -3.5 M18 12 l1 -1 l1 1 l-1 1 Z",
        "sd-card":     "M6 2 h8 l6 6 v12 a2 2 0 0 1 -2 2 H6 a2 2 0 0 1 -2 -2 V4 a2 2 0 0 1 2 -2 Z M8 6 v3 M11 6 v3 M14 8 v2",
        "lock":        "M5 11 h14 a2 2 0 0 1 2 2 v7 a2 2 0 0 1 -2 2 H5 a2 2 0 0 1 -2 -2 v-7 a2 2 0 0 1 2 -2 Z M7 11 V7 a5 5 0 0 1 10 0 v4",
        "wifi":        "M12 20 h.01 M2 8.82 a15 15 0 0 1 20 0 M5 12.859 a10 10 0 0 1 14 0 M8.5 16.429 a5 5 0 0 1 7 0",
        "refresh":     "M3 12 a9 9 0 0 1 9 -9 a9.75 9.75 0 0 1 6.74 2.74 L21 8 M21 3 v5 h-5 M21 12 a9 9 0 0 1 -9 9 a9.75 9.75 0 0 1 -6.74 -2.74 L3 16 M8 16 H3 v5",
        "x-circle":    "M22 12 A10 10 0 1 1 2 12 A10 10 0 1 1 22 12 Z M15 9 l-6 6 M9 9 l6 6",
        "eject":       "M12 5 L4 14 h16 Z M4 19 h16"
    })

    Accessible.ignored: true

    Shape {
        anchors.centerIn: parent
        width: 24
        height: 24
        scale: root.size / 24
        preferredRendererType: Shape.CurveRenderer   // antialiased edges without multisampling

        ShapePath {
            strokeColor: root.color
            strokeWidth: root.strokeWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.paths[root.name] || "" }
        }
    }
}
