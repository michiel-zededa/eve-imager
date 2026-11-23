/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025-2026 ZEDEDA, Inc.
 *
 * EveConfigurator -- writes EVE-OS configuration into an installer image that
 * has just been written to a drive.
 *
 * Most of it goes into the CONFIG partition (a small FAT partition with the
 * GPT name "CONFIG"), the same place the "conf" directory of a custom EVE-OS
 * build ends up:
 *
 *   server                          controller address
 *   root-certificate.pem            controller root certificate (private CA)
 *   onboard.cert.pem / .key.pem     onboarding certificate and key
 *   authorized_keys                 SSH key for the debug console
 *   DevicePortConfig/override.json  network interfaces, WiFi, proxy, proxy CA
 *   bootstrap-config.pb             bootstrap config exported by the controller
 *   grub.cfg                        installer options (disks, serial, console)
 *
 * One hardware-specific change goes into the EFI system partition:
 *
 *   config.txt                      OnLogic FR201 boot configuration
 *
 * Every function here throws std::runtime_error with a message meant for the
 * user when something that was asked for cannot be done.
 */

#ifndef EVECONFIGURATOR_H
#define EVECONFIGURATOR_H

#include <QByteArray>
#include <QString>
#include <QVariantMap>

class DeviceWrapper;
class DeviceWrapperFatPartition;

class EveConfigurator
{
public:
    /*
     * Apply the configuration to the drive behind `dw`.
     *
     * config keys (all optional):
     *
     *   controllerUrl        controller host name, e.g. "zedcloud.zededa.net"
     *   rootCertPath         file: controller root certificate
     *   onboardCertPath      file: onboarding certificate
     *   onboardKeyPath       file: onboarding key
     *   authorizedKeys       text: SSH public key(s)
     *
     *   interfaces           list of maps, one per network port:
     *       ifName             e.g. "eth0"
     *       mode               "dhcp" (default) | "static"
     *       isMgmt             bool, default true
     *       ip                 "192.168.1.100/24"       (static)
     *       gateway            "192.168.1.1"            (static)
     *       dns                comma-separated IPs      (static)
     *       ntp                comma-separated hosts or IPs
     *       vlans              list of maps: tag, mode, isMgmt, ip, gateway, dns
     *   wifiSsid, wifiPassword
     *
     *   proxyEnabled         bool
     *   proxyAddress         "proxy.example.com:3128" (a scheme is accepted)
     *   proxyExceptions      comma-separated hosts / domains / networks
     *   proxyPacUrl          URL of a PAC (proxy auto-config) file
     *   proxyPacFilePath     file: PAC file to embed
     *   proxyInspects        bool: the proxy intercepts TLS
     *   proxyCertPaths       list of files: proxy CA certificates
     *
     *   installDisk          e.g. "nvme0n1"
     *   persistDisk          e.g. "sda" or "sdb,sdc"
     *   nukeDisks            e.g. "sda,sdb"
     *   softSerial           letters, digits, ".", "-", "_"
     *   console              "" (image default) | "vga" | "serial"
     *   rebootAfterInstall   bool
     *
     *   hardware             "" | "fr201" | "fr201-nvme"
     *   bootstrapConfigPath  file: bootstrap-config.pb
     *
     * Returns true if anything was written, false if the configuration asks
     * for nothing.
     */
    static bool apply(DeviceWrapper &dw, const QVariantMap &config);

    /*
     * Check a configuration without touching a drive: builds everything in
     * memory and reads every file it names. Returns an empty string if it is
     * fine, otherwise the message to show.
     */
    static QString validate(const QVariantMap &config);

    /* True if the configuration would change anything in the image. */
    static bool hasAnything(const QVariantMap &config);

    /* --- generators (also used by the tests) --- */

    /* DevicePortConfig/override.json, or empty if no network settings are set. */
    static QByteArray buildOverrideJson(const QVariantMap &config);

    /*
     * The block of GRUB commands for the installer options, or empty if none
     * are set. mergeGrubCfg() puts it into an existing grub.cfg.
     */
    static QByteArray buildGrubBlock(const QVariantMap &config);
    static QByteArray mergeGrubCfg(const QByteArray &existing, const QByteArray &block);

    /* config.txt with the two changes the OnLogic FR201 needs. */
    static QByteArray patchConfigTxtForFr201(const QByteArray &configTxt);

    /* A certificate file as PEM text (accepts PEM and binary DER). */
    static QByteArray readCertificateAsPem(const QString &path, const QString &what);

    /* EVE-OS refuses a DevicePortConfig file larger than this. */
    static constexpr int MaxOverrideJsonBytes = 16384;

private:
    static DeviceWrapperFatPartition *findPartition(DeviceWrapper &dw, bool efiSystem);
    static QByteArray readFileLimited(const QString &path, const QString &what, qint64 maxBytes);
};

#endif // EVECONFIGURATOR_H
