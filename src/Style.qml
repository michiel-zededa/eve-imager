/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 ZEDEDA, Inc.
 */

pragma Singleton

import QtQuick
import RpiImager

Item {
    id: root

    // === TEXT SCALING ===
    // Platform text-scaling factor (1.0 = default, 1.5 = 150%, etc.)
    // Reflects OS-level accessibility preferences (Windows "Make text bigger",
    // GNOME text-scaling-factor, etc.) that Qt QML does not honour automatically.
    // DPI normalization is handled by Qt via font.pointSize + screen logical DPI.
    readonly property real textScale: PlatformHelper.textScaleFactor

    // Font-specific scale: DPI correction (72/96 on Windows/Linux, 1.0 on macOS)
    // multiplied by the accessibility text scale. Applied only to font sizes so
    // that layout, spacing, and button sizes are unaffected.
    readonly property real fontScale: PlatformHelper.fontDpiCorrection * textScale

    // Scale a base value by the text scaling factor, rounding to nearest int.
    function scaled(base) { return Math.round(base * textScale) }

    // === COLORS — ZEDEDA brand palette ===
    readonly property color mainBackgroundColor: "#ffffff"

    // ZEDEDA primary navy — replaces raspberry red as the brand anchor color
    readonly property color zededaNavy:  "#134468"
    readonly property color zededaNavyDark: "#0d3050"   // hover / focus darker shade
    readonly property color zededaOrange: "#FFA500"      // CTA accent (Write button)
    readonly property color zededaLightBlue: "#d1eaff"   // subtle backgrounds / hover fill
    readonly property color zededaCharcoal: "#32373c"    // secondary buttons

    // Keep the alias so existing references to `raspberryRed` throughout QML still compile,
    // but they now resolve to ZEDEDA navy.
    readonly property color raspberryRed: zededaNavy
    readonly property color transparent: "transparent"

    // Secondary / ghost button (outline style)
    readonly property color buttonBackgroundColor: mainBackgroundColor
    readonly property color buttonForegroundColor: zededaNavy
    readonly property color buttonFocusedBackgroundColor: zededaLightBlue
    readonly property color buttonHoveredBackgroundColor: "#f0f4f8"

    // Primary filled button (Next / Write)
    readonly property color button2BackgroundColor: zededaNavy
    readonly property color button2ForegroundColor: mainBackgroundColor
    readonly property color button2FocusedBackgroundColor: zededaNavyDark
    readonly property color button2HoveredBackgroundColor: zededaLightBlue
    readonly property color button2HoveredForegroundColor: zededaNavy

    // Orange accent for the primary write/action CTA
    readonly property color ctaBackgroundColor: zededaOrange
    readonly property color ctaForegroundColor: mainBackgroundColor
    readonly property color ctaHoveredBackgroundColor: "#e69500"  // slightly darker orange

    readonly property color titleBackgroundColor: "#f5f8fa"
    readonly property color titleSeparatorColor: "#d8d8d8"
    readonly property color popupBorderColor: "#d8d8d8"

    readonly property color listViewRowBackgroundColor: "#ffffff"
    readonly property color listViewHoverRowBackgroundColor: titleBackgroundColor
    readonly property color listViewHighlightColor: zededaLightBlue

    // Utility translucent colors
    readonly property color translucentWhite10: Qt.rgba(255, 255, 255, 0.1)
    readonly property color translucentWhite30: Qt.rgba(255, 255, 255, 0.3)

    readonly property color textDescriptionColor: "#4a4a4a"

    // Sidebar
    readonly property color sidebarActiveBackgroundColor: zededaNavy
    readonly property color sidebarTextOnActiveColor: "#ffffff"
    readonly property color sidebarTextOnInactiveColor: zededaNavy
    readonly property color sidebarTextDisabledColor: "#a1a1a1"
    readonly property color sidebarControlBorderColor: "#767676"
    readonly property color sidebarBackgroundColour: mainBackgroundColor
    readonly property color sidebarBorderColour: zededaNavy

    // Metadata / captions in list views
    readonly property color textMetadataColor: "#a1a1a1"
    readonly property color subtitleColor: "#ffffff"

    // Progress bar
    readonly property color progressBarTextColor: "white"
    readonly property color progressBarVerifyForegroundColor: "#2e7d32"   // green for verify phase
    readonly property color progressBarBackgroundColor: zededaNavy
    readonly property color progressBarWritingForegroundColor: zededaOrange
    readonly property color progressBarTrackColor: titleBackgroundColor

    readonly property color lanbarBackgroundColor: "#fff9e6"

    // Form controls
    readonly property color formLabelColor: "#4a4a4a"
    readonly property color formLabelErrorColor: "#c62828"
    readonly property color formLabelDisabledColor: "#a1a1a1"
    readonly property color formControlActiveColor: zededaNavy

    readonly property color embeddedModeInfoTextColor: "#ffffff"

    // Status indicators
    readonly property color statusSuccess: "#2e7d32"
    readonly property color statusError:   "#c62828"
    readonly property color statusWarning: zededaOrange
    readonly property color statusInfo:    "#056094"

    // Focus / outline
    readonly property color focusOutlineColor: zededaNavy
    readonly property int focusOutlineWidth: 2
    readonly property int focusOutlineRadius: 4
    readonly property int focusOutlineMargin: -4

    // === FONTS ===
    readonly property alias fontFamily: roboto.name
    readonly property alias fontFamilyLight: robotoLight.name
    readonly property alias fontFamilyBold: robotoBold.name

    // Font sizes (point sizes — DPI-aware, scaled by Qt based on screen logical DPI)
    // Additionally scaled by the OS accessibility text-scaling factor.
    // Base scale (single source of truth)
    readonly property real fontSizeXs: Math.round(12 * fontScale)
    readonly property real fontSizeSm: Math.round(14 * fontScale)
    readonly property real fontSizeMd: Math.round(16 * fontScale)
    readonly property real fontSizeXl: Math.round(24 * fontScale)

    // Role tokens mapped to base scale
    readonly property real fontSizeTitle: fontSizeXl
    readonly property real fontSizeHeading: fontSizeMd
    readonly property real fontSizeLargeHeading: fontSizeMd
    readonly property real fontSizeFormLabel: fontSizeSm
    readonly property real fontSizeSubtitle: fontSizeSm
    readonly property real fontSizeDescription: fontSizeXs
    readonly property real fontSizeInput: fontSizeSm
    readonly property real fontSizeCaption: fontSizeXs
    readonly property real fontSizeSmall: fontSizeXs
    readonly property real fontSizeSidebarItem: fontSizeSm

    // === SPACING (scaled by text scale factor) ===
    readonly property int spacingXXSmall: scaled(2)
    readonly property int spacingXSmall: scaled(5)
    readonly property int spacingTiny: scaled(8)
    readonly property int spacingSmall: scaled(10)
    readonly property int spacingSmallPlus: scaled(12)
    readonly property int spacingMedium: scaled(15)
    readonly property int spacingLarge: scaled(20)
    readonly property int spacingExtraLarge: scaled(30)

    // === SIZES (scaled by text scale factor) ===
    readonly property int buttonHeightStandard: scaled(40)
    readonly property int buttonWidthMinimum: scaled(120)
    readonly property int buttonWidthSkip: scaled(150)

    readonly property int sectionMaxWidth: scaled(500)
    readonly property int sectionMargins: scaled(24)
    readonly property int sectionPadding: scaled(16)
    readonly property int sectionBorderWidth: 1          // not scaled — visual decoration
    readonly property int sectionBorderRadius: 8         // not scaled — visual decoration
    readonly property int listItemBorderRadius: 5        // not scaled — visual decoration
    readonly property int listItemPadding: scaled(15)
    readonly property int cardPadding: scaled(20)
    readonly property int scrollBarWidth: scaled(10)
    readonly property int sidebarWidth: scaled(200)
    readonly property int sidebarMinWidth: scaled(150)
    readonly property int sidebarMaxWidth: scaled(350)
    readonly property int sidebarDragHandleWidth: scaled(8)
    readonly property color sidebarDragHandleHoverColor: listViewHoverRowBackgroundColor
    readonly property color sidebarDragHandleHoverBackground: Qt.rgba(
        listViewHoverRowBackgroundColor.r,
        listViewHoverRowBackgroundColor.g,
        listViewHoverRowBackgroundColor.b, 0.3)
    readonly property int sidebarItemBorderRadius: 4     // not scaled — visual decoration
    // Embedded-mode overrides (0 radius to avoid software renderer artifacts)
    readonly property int sectionBorderRadiusEmbedded: 0
    readonly property int listItemBorderRadiusEmbedded: 0
    readonly property int sidebarItemBorderRadiusEmbedded: 0
    readonly property int buttonBorderRadiusEmbedded: 0
    // Sidebar item heights
    readonly property int sidebarItemHeight: buttonHeightStandard
    readonly property int sidebarSubItemHeight: sidebarItemHeight - scaled(12)

    // === LAYOUT (scaled by text scale factor) ===
    readonly property int formColumnSpacing: scaled(20)
    readonly property int formRowSpacing: scaled(15)
    readonly property int stepContentMargins: scaled(24)
    readonly property int stepContentSpacing: scaled(16)

    // Font loaders
    FontLoader { id: roboto;      source: "fonts/Roboto-Regular.ttf" }
    FontLoader { id: robotoLight; source: "fonts/Roboto-Light.ttf" }
    FontLoader { id: robotoBold;  source: "fonts/Roboto-Bold.ttf" }
}
