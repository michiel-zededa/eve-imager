/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2026 ZEDEDA, Inc.
 *
 * A rounded progress bar: a pale track with an accent fill. In indeterminate
 * mode a short segment slides along the track.
 */

import QtQuick
import QtQuick.Templates as T

import RpiImager

T.ProgressBar {
    id: control

    property color fillColor: Style.accent

    implicitWidth: Style.scaled(200)
    implicitHeight: Style.scaled(10)

    background: Rectangle {
        radius: height / 2
        color: Style.track
    }

    contentItem: Item {
        clip: true

        Rectangle {
            visible: !control.indeterminate
            width: Math.max(control.visualPosition > 0 ? height : 0, control.visualPosition * parent.width)
            height: parent.height
            radius: height / 2
            color: control.fillColor
            Behavior on width { NumberAnimation { duration: 150 } }
        }

        Rectangle {
            id: slider
            visible: control.indeterminate
            width: parent.width * 0.3
            height: parent.height
            radius: height / 2
            color: control.fillColor

            SequentialAnimation on x {
                running: control.indeterminate && control.visible
                loops: Animation.Infinite
                NumberAnimation {
                    from: -slider.width
                    to: control.width
                    duration: 1400
                    easing.type: Easing.InOutQuad
                }
            }
        }
    }
}
