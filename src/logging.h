/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Raspberry Pi Ltd
 */

#ifndef LOGGING_H
#define LOGGING_H

#include <QLoggingCategory>

// Declare logging categories for each major subsystem.
// Usage:
//   #include "logging.h"
//   qCDebug(lcDownload) << "bytes received:" << n;
//   qCWarning(lcWrite)  << "sync failed";
//
// At runtime, categories can be filtered via QT_LOGGING_RULES, e.g.:
//   QT_LOGGING_RULES="rpi.download=false;rpi.fat.debug=false" ./rpi-imager

Q_DECLARE_LOGGING_CATEGORY(lcDownload)      // HTTP download / progress
Q_DECLARE_LOGGING_CATEGORY(lcWrite)         // Device write path
Q_DECLARE_LOGGING_CATEGORY(lcVerify)        // Post-write verification
Q_DECLARE_LOGGING_CATEGORY(lcCache)         // AsyncCacheWriter
Q_DECLARE_LOGGING_CATEGORY(lcFat)           // FAT partition operations
Q_DECLARE_LOGGING_CATEGORY(lcDriveList)     // Drive enumeration
Q_DECLARE_LOGGING_CATEGORY(lcIcons)         // Icon multi-fetcher
Q_DECLARE_LOGGING_CATEGORY(lcPlatform)      // Platform quirks
Q_DECLARE_LOGGING_CATEGORY(lcRpiboot)       // rpiboot protocol
Q_DECLARE_LOGGING_CATEGORY(lcFastboot)      // fastboot protocol
Q_DECLARE_LOGGING_CATEGORY(lcEve)           // EVE OS release fetcher / configurator

#endif // LOGGING_H
