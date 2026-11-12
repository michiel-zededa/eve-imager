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

    // === THEME ===
    // The look follows the ZEDEDA product UI (the same tokens as the EVE Netboot
    // Installer web UI): a light grey page, white cards with thin borders, one
    // purple accent, status pills. Every colour below has a light and a dark
    // value; nothing else in the QML should hard-code a colour.
    //
    // themeMode is "system" (follow the OS), "light" or "dark". main.qml loads
    // it from the settings and the appearance button in the top bar changes it.
    property string themeMode: "system"
    readonly property bool dark: themeMode === "dark"
                                 || (themeMode !== "light" && Qt.styleHints.colorScheme === Qt.ColorScheme.Dark)

    // --- Base palette ---
    readonly property color bg:            dark ? "#1d1e21" : "#f7f7f9"   // window / page
    readonly property color surface:       dark ? "#26272b" : "#ffffff"   // cards, inputs, dialogs
    readonly property color surface2:      dark ? "#2e3035" : "#f2f3f5"   // hover fill, chips, tracks
    readonly property color border:        dark ? "#3a3c42" : "#e5e7eb"
    readonly property color text:          dark ? "#e8e8ea" : "#1f2328"
    readonly property color muted:         dark ? "#9b9da5" : "#6b7079"   // secondary text
    readonly property color disabledText:  dark ? "#6f7178" : "#9a9da3"
    readonly property color accent:        dark ? "#a78bfa" : "#7c3aed"   // primary buttons, active markers
    readonly property color accentStrong:  dark ? "#c4b5fd" : "#6d28d9"   // hover / pressed
    readonly property color accentSoft:    dark ? "#352f4d" : "#ede8fd"   // selected rows, active step
    readonly property color accentText:    dark ? "#c4b5fd" : "#6d28d9"   // links, text on accentSoft
    readonly property color accentContrast:      dark ? "#1d1e21" : "#ffffff"   // text on accent
    readonly property color scrim:         dark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(0.06, 0.09, 0.16, 0.35)

    // --- Status (text / fill / border), used by pills and banners ---
    readonly property color ok:            dark ? "#7ad19b" : "#1e7b46"
    readonly property color okBg:          dark ? "#1f3a2a" : "#e8f5ee"
    readonly property color okBorder:      dark ? "#2f5a40" : "#b5dfc5"
    readonly property color warn:          dark ? "#e2c773" : "#6b5413"
    readonly property color warnBg:        dark ? "#3a3320" : "#f4efe2"
    readonly property color warnBorder:    dark ? "#5a4d2a" : "#d9c99c"
    readonly property color err:           dark ? "#f2938a" : "#b42318"
    readonly property color errBg:         dark ? "#43231f" : "#fdecea"
    readonly property color errBorder:     dark ? "#6b332d" : "#f3bab4"
    readonly property color info:          dark ? "#a9b4f5" : "#3743a6"
    readonly property color infoBg:        dark ? "#262c4a" : "#eaedfb"
    readonly property color infoBorder:    dark ? "#39426e" : "#bcc5f1"
    readonly property color neutral:       dark ? "#c4b5fd" : "#5b21b6"
    readonly property color neutralBg:     dark ? "#332c4a" : "#f1ecfd"
    readonly property color neutralBorder: dark ? "#4b4170" : "#d6c8f8"
    readonly property color track:         dark ? "#34363c" : "#eceef1"   // progress bar track

    // === COLORS — role tokens used throughout the QML ===
    readonly property color mainBackgroundColor: bg

    // Older names kept so existing references keep working; they resolve to
    // the palette above.
    readonly property color zededaNavy: text
    readonly property color zededaNavyDark: text
    readonly property color zededaOrange: accent
    readonly property color zededaLightBlue: accentSoft
    readonly property color zededaCharcoal: text
    readonly property color raspberryRed: accent
    readonly property color transparent: "transparent"

    // Secondary button (white with a border)
    readonly property color buttonBackgroundColor: surface
    readonly property color buttonForegroundColor: text
    readonly property color buttonFocusedBackgroundColor: surface2
    readonly property color buttonHoveredBackgroundColor: surface2

    // Primary button (filled accent)
    readonly property color button2BackgroundColor: accent
    readonly property color button2ForegroundColor: accentContrast
    readonly property color button2FocusedBackgroundColor: accentStrong
    readonly property color button2HoveredBackgroundColor: accentStrong
    readonly property color button2HoveredForegroundColor: accentContrast

    readonly property color ctaBackgroundColor: accent
    readonly property color ctaForegroundColor: accentContrast
    readonly property color ctaHoveredBackgroundColor: accentStrong

    readonly property color titleBackgroundColor: surface2
    readonly property color titleSeparatorColor: border
    readonly property color popupBorderColor: border

    readonly property color listViewRowBackgroundColor: surface
    readonly property color listViewHoverRowBackgroundColor: surface2
    readonly property color listViewHighlightColor: accentSoft

    // Utility translucent colors
    readonly property color translucentWhite10: Qt.rgba(1, 1, 1, 0.1)
    readonly property color translucentWhite30: Qt.rgba(1, 1, 1, 0.3)

    readonly property color textDescriptionColor: muted

    // Sidebar
    readonly property color sidebarActiveBackgroundColor: accentSoft
    readonly property color sidebarTextOnActiveColor: accentText
    readonly property color sidebarTextOnInactiveColor: text
    readonly property color sidebarTextDisabledColor: muted
    readonly property color sidebarControlBorderColor: border
    readonly property color sidebarBackgroundColour: bg
    readonly property color sidebarBorderColour: border

    // Metadata / captions in list views
    readonly property color textMetadataColor: muted
    readonly property color subtitleColor: muted

    // Progress bar
    readonly property color progressBarTextColor: text
    readonly property color progressBarVerifyForegroundColor: ok
    readonly property color progressBarBackgroundColor: track
    readonly property color progressBarWritingForegroundColor: accent
    readonly property color progressBarTrackColor: track

    readonly property color lanbarBackgroundColor: warnBg

    // Form controls
    readonly property color formLabelColor: text
    readonly property color formLabelErrorColor: err
    readonly property color formLabelDisabledColor: disabledText
    readonly property color formControlActiveColor: accent
    readonly property color formControlBorderColor: dark ? "#55585f" : "#c4c7cc"   // unchecked boxes / radios

    readonly property color embeddedModeInfoTextColor: accentContrast

    // Status indicators
    readonly property color statusSuccess: ok
    readonly property color statusError:   err
    readonly property color statusWarning: warn
    readonly property color statusInfo:    info

    // Focus / outline
    readonly property color focusOutlineColor: accent
    readonly property int focusOutlineWidth: 2
    readonly property int focusOutlineRadius: 10
    readonly property int focusOutlineMargin: -4

    // === FONTS ===
    // Inter, in four static weights that all register under the family
    // "Inter"; pick the weight with font.weight (or font.bold for 700).
    readonly property string fontFamily: inter.status === FontLoader.Ready ? inter.name : "sans-serif"
    readonly property string fontFamilyLight: fontFamily
    readonly property string fontFamilyBold: fontFamily
    readonly property string fontFamilyMono: Qt.platform.os === "osx" ? "Menlo"
                                             : Qt.platform.os === "windows" ? "Consolas" : "monospace"
    readonly property int fontWeightMedium: Font.Medium       // 500: buttons, labels, active items
    readonly property int fontWeightSemiBold: Font.DemiBold   // 600: headings

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
    readonly property int sectionBorderRadius: 16        // cards — not scaled, visual decoration
    readonly property int listItemBorderRadius: 10       // not scaled — visual decoration
    readonly property int controlBorderRadius: 10        // buttons, inputs, selects
    readonly property int pillBorderRadius: 999
    readonly property int listItemPadding: scaled(15)
    readonly property int cardPadding: scaled(20)
    readonly property int scrollBarWidth: scaled(10)
    readonly property int sidebarWidth: scaled(220)
    readonly property int topBarHeight: scaled(52)
    readonly property int sidebarMinWidth: scaled(150)
    readonly property int sidebarMaxWidth: scaled(350)
    readonly property int sidebarDragHandleWidth: scaled(8)
    readonly property color sidebarDragHandleHoverColor: listViewHoverRowBackgroundColor
    readonly property color sidebarDragHandleHoverBackground: Qt.rgba(
        listViewHoverRowBackgroundColor.r,
        listViewHoverRowBackgroundColor.g,
        listViewHoverRowBackgroundColor.b, 0.3)
    readonly property int sidebarItemBorderRadius: 12    // not scaled — visual decoration
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
    FontLoader { id: inter;         source: "fonts/Inter-Regular.ttf" }
    FontLoader { id: interMedium;   source: "fonts/Inter-Medium.ttf" }
    FontLoader { id: interSemiBold; source: "fonts/Inter-SemiBold.ttf" }
    FontLoader { id: interBold;     source: "fonts/Inter-Bold.ttf" }
}
