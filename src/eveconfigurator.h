/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 ZEDEDA, Inc.
 *
 * EveConfigurator — writes EVE OS config files into the CONFIG FAT partition
 * of an already-written installer image.
 *
 * The CONFIG partition is identified by GPT partition name "CONFIG".
 * It is a 1 MB FAT16 filesystem and always contains at minimum:
 *   - DevicePortConfig/   (directory)
 *   - onboard.cert.pem    (default placeholder)
 *   - onboard.key.pem     (default placeholder)
 *   - server              (default empty or zedcloud URL)
 *
 * Files written by this class:
 *   - server                          if controllerUrl is set
 *   - DevicePortConfig/override.json  if networkMode=="static" or proxyUrl set
 *   - onboard.cert.pem                if onboardCertPath is set
 *   - onboard.key.pem                 if onboardKeyPath is set
 *   - soft_serial                     if deviceSerial is set
 */

#ifndef EVECONFIGURATOR_H
#define EVECONFIGURATOR_H

#include <QVariantMap>
#include <QByteArray>

class DeviceWrapper;
class DeviceWrapperFatPartition;

class EveConfigurator
{
public:
    /*
     * Apply EVE config to a DeviceWrapper that wraps the destination device
     * (after the installer image has been written to it).
     *
     * config keys (all optional strings):
     *   controllerUrl   — EVE controller FQDN, e.g. "zedcloud.zededa.net"
     *   networkMode     — "dhcp" (default) | "static"
     *   staticIp        — CIDR, e.g. "192.168.1.100/24"  (static only)
     *   gateway         — e.g. "192.168.1.1"              (static only)
     *   dns             — comma-separated, e.g. "8.8.8.8" (static only)
     *   proxyUrl        — e.g. "http://proxy.example.com:3128"
     *   onboardCertPath — local filesystem path to onboard.cert.pem
     *   onboardKeyPath  — local filesystem path to onboard.key.pem
     *   deviceSerial    — soft serial string
     *
     * Returns true if any files were written, false on error (throws on hard error).
     */
    static bool apply(DeviceWrapper &dw, const QVariantMap &config);

    /*
     * Scan the GPT table in dw for a partition named "CONFIG".
     * Returns a new DeviceWrapperFatPartition on success, nullptr if not found.
     * Caller takes ownership of the returned object.
     */
    static DeviceWrapperFatPartition *findConfigPartition(DeviceWrapper &dw);

private:
    /* Build DevicePortConfig/override.json content, or empty if not needed. */
    static QByteArray buildOverrideJson(const QVariantMap &config);
    /* Build grub.cfg content for installer disk/boot params, or empty if not needed. */
    static QByteArray buildGrubCfg(const QVariantMap &config);
};

#endif // EVECONFIGURATOR_H
