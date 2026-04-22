/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 ZEDEDA, Inc.
 *
 * EveConfigurator -- writes EVE OS config files into the CONFIG FAT partition
 * of an already-written installer image.
 *
 * The CONFIG partition is identified by GPT partition name "CONFIG".
 * It is a 1 MB FAT partition and always contains at minimum:
 *   - DevicePortConfig/   (directory)
 *   - server              (default empty or zedcloud URL)
 *
 * Files written by this class (all optional):
 *   - server                          if controllerUrl is set
 *   - root-certificate.pem            if rootCertPath is set
 *   - DevicePortConfig/override.json  if networkMode=="static", proxyUrl,
 *                                     or wifiSsid is set
 *   - authorized_keys                 if authorizedKeys is set
 *   - grub.cfg                        if installDisk, persistDisk, or
 *                                     rebootAfterInstall is set
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
     * config keys (all optional):
     *   controllerUrl      - EVE controller FQDN, e.g. "zedcloud.zededa.net"
     *   rootCertPath       - local path to controller CA certificate (.pem)
     *   networkMode        - "dhcp" (default) | "static"
     *   staticIp           - CIDR, e.g. "192.168.1.100/24"  (static only)
     *   gateway            - e.g. "192.168.1.1"              (static only)
     *   dns                - comma-separated, e.g. "8.8.8.8" (static only)
     *   proxyUrl           - e.g. "http://proxy.example.com:3128"
     *   wifiSsid           - WiFi network SSID
     *   wifiPassword       - WiFi WPA2 pre-shared key
     *   authorizedKeys     - SSH public key text for authorized_keys
     *   installDisk        - Linux device name, e.g. "nvme0n1"
     *   persistDisk        - Linux device name for /persist, e.g. "sda"
     *   rebootAfterInstall - bool, add eve_reboot_after_install to grub.cfg
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
