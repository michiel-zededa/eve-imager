/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025-2026 ZEDEDA, Inc.
 */

#include "eveconfigurator.h"
#include "devicewrapper.h"
#include "devicewrapperfatpartition.h"
#include "devicewrapperstructs.h"

#include <QCoreApplication>
#include <QDebug>
#include <QFile>
#include <QFileInfo>
#include <QHostAddress>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QString>
#include <QUrl>

#include <cstring>
#include <memory>
#include <stdexcept>

namespace {

// Messages thrown from here are shown to the user as they are.
[[noreturn]] void fail(const QString &message)
{
    throw std::runtime_error(message.toStdString());
}

QString tr(const char *text)
{
    return QCoreApplication::translate("EveConfigurator", text);
}

QString str(const QVariantMap &m, const char *key)
{
    return m.value(QLatin1String(key)).toString().trimmed();
}

QStringList splitList(const QString &s)
{
    QStringList out;
    const QStringList parts = s.split(QRegularExpression(QStringLiteral("[,;\\s]+")), Qt::SkipEmptyParts);
    for (const QString &p : parts)
        out << p.trimmed();
    return out;
}

// EVE-OS numbers, from pkg/pillar/types/dpc.go
const int DhcpTypeStatic = 1;
const int DhcpTypeClient = 4;
const int ProxyTypeHttp = 0;
const int ProxyTypeHttps = 1;
const int L2LinkTypeVlan = 1;
const int WirelessTypeWifi = 2;
const int WifiKeySchemeWpaPsk = 1;

// Go's net.IP refuses anything that is not an address, and one refused value
// makes EVE-OS drop the whole file: so every address is checked here.
QString checkedIp(const QString &value, const QString &what)
{
    QHostAddress a;
    if (!a.setAddress(value))
        fail(tr("%1: \"%2\" is not an IP address.").arg(what, value));
    return a.toString();
}

QString checkedCidr(const QString &value, const QString &what)
{
    const int slash = value.indexOf(QLatin1Char('/'));
    bool ok = false;
    const int prefix = slash > 0 ? value.mid(slash + 1).toInt(&ok) : -1;
    QHostAddress a;
    if (slash <= 0 || !ok || !a.setAddress(value.left(slash)))
        fail(tr("%1: \"%2\" must be an address with a prefix length, for example 192.168.1.100/24.").arg(what, value));
    const int maxPrefix = a.protocol() == QAbstractSocket::IPv6Protocol ? 128 : 32;
    if (prefix < 1 || prefix > maxPrefix)
        fail(tr("%1: the prefix length in \"%2\" must be between 1 and %3.").arg(what, value).arg(maxPrefix));
    return a.toString() + QLatin1Char('/') + QString::number(prefix);
}

// Addressing of one port (an interface or a VLAN on it)
void addAddressing(QJsonObject &port, const QVariantMap &src, const QString &label)
{
    if (str(src, "mode") == QLatin1String("static")) {
        port[QStringLiteral("Dhcp")] = DhcpTypeStatic;

        const QString ip = str(src, "ip");
        if (ip.isEmpty())
            fail(tr("%1 is set to a static address but has no IP address.").arg(label));
        port[QStringLiteral("AddrSubnet")] = checkedCidr(ip, tr("%1, IP address").arg(label));

        const QString gateway = str(src, "gateway");
        if (!gateway.isEmpty())
            port[QStringLiteral("Gateway")] = checkedIp(gateway, tr("%1, gateway").arg(label));

        QJsonArray dns;
        const QStringList servers = splitList(str(src, "dns"));
        for (const QString &s : servers)
            dns.append(checkedIp(s, tr("%1, DNS server").arg(label)));
        if (!dns.isEmpty())
            port[QStringLiteral("DnsServers")] = dns;
    } else {
        port[QStringLiteral("Dhcp")] = DhcpTypeClient;
    }

    const QStringList ntp = splitList(str(src, "ntp"));
    if (!ntp.isEmpty()) {
        static const QRegularExpression hostRe(QStringLiteral("^[A-Za-z0-9._:-]+$"));
        QJsonArray servers;
        for (const QString &s : ntp) {
            if (!hostRe.match(s).hasMatch())
                fail(tr("%1, NTP server: \"%2\" is not a host name or IP address.").arg(label, s));
            servers.append(s);
        }
        port[QStringLiteral("NTPServers")] = servers;
        // EVE-OS up to 13.x has one NTP server per port, and only as an address
        QHostAddress first;
        if (first.setAddress(ntp.first()))
            port[QStringLiteral("NtpServer")] = first.toString();
    }
}

struct ProxySettings {
    bool active = false;
    QJsonArray proxies;
    QString exceptions;
    QString pacUrl;
    QByteArray pacFile;          // already base64
    QJsonArray certs;            // base64 of PEM text, as Go's [][]byte
};

ProxySettings readProxy(const QVariantMap &config)
{
    ProxySettings p;
    if (!config.value(QStringLiteral("proxyEnabled")).toBool())
        return p;

    const QString address = str(config, "proxyAddress");
    if (!address.isEmpty()) {
        // "host:port", with or without a scheme in front
        const QUrl url = QUrl::fromUserInput(address.contains(QLatin1String("://")) ? address
                                                                                    : QStringLiteral("http://") + address);
        const QString host = url.host();
        const int port = url.port(-1);
        if (!url.isValid() || host.isEmpty())
            fail(tr("Proxy address: \"%1\" is not a host name and port, for example proxy.example.com:3128.").arg(address));
        if (port < 1 || port > 65535)
            fail(tr("Proxy address: \"%1\" needs a port number, for example proxy.example.com:3128.").arg(address));
        for (int type : { ProxyTypeHttps, ProxyTypeHttp }) {
            QJsonObject entry;
            entry[QStringLiteral("Server")] = host;
            entry[QStringLiteral("Port")] = port;
            entry[QStringLiteral("Type")] = type;
            p.proxies.append(entry);
        }
    }

    p.exceptions = splitList(str(config, "proxyExceptions")).join(QLatin1Char(','));

    const QString pacPath = str(config, "proxyPacFilePath");
    p.pacUrl = str(config, "proxyPacUrl");
    if (!pacPath.isEmpty()) {
        QFile f(pacPath);
        if (!f.open(QIODevice::ReadOnly))
            fail(tr("Cannot read the PAC file %1: %2").arg(pacPath, f.errorString()));
        const QByteArray pac = f.readAll();
        if (pac.trimmed().isEmpty())
            fail(tr("The PAC file %1 is empty.").arg(pacPath));
        p.pacFile = pac.toBase64();
        p.pacUrl.clear();        // the embedded file takes the place of the URL
    } else if (!p.pacUrl.isEmpty()) {
        const QUrl url(p.pacUrl);
        if (!url.isValid() || url.host().isEmpty()
            || (url.scheme() != QLatin1String("http") && url.scheme() != QLatin1String("https")))
            fail(tr("PAC URL: \"%1\" must start with http:// or https://.").arg(p.pacUrl));
    }

    if (config.value(QStringLiteral("proxyInspects")).toBool()) {
        const QStringList paths = config.value(QStringLiteral("proxyCertPaths")).toStringList();
        for (const QString &path : paths) {
            if (path.trimmed().isEmpty())
                continue;
            const QByteArray pem = EveConfigurator::readCertificateAsPem(path.trimmed(), tr("proxy CA certificate"));
            p.certs.append(QString::fromLatin1(pem.toBase64()));
        }
        if (p.certs.isEmpty())
            fail(tr("The proxy is set to inspect encrypted traffic, but no proxy CA certificate was chosen."));
    }

    if (p.proxies.isEmpty() && p.pacFile.isEmpty() && p.pacUrl.isEmpty() && p.certs.isEmpty())
        fail(tr("The proxy is switched on but has no address, PAC file or certificate."));

    p.active = true;
    return p;
}

// EVE-OS trusts the proxy certificates of every port for all its
// connections, so they are written once (on the first management port): the
// file may be 16 KB at most and each certificate takes 2 KB or more.
void addProxy(QJsonObject &port, const ProxySettings &p, bool withLegacyCertKey, bool *certsPlaced)
{
    if (!p.active)
        return;
    if (!p.proxies.isEmpty())
        port[QStringLiteral("Proxies")] = p.proxies;
    if (!p.exceptions.isEmpty())
        port[QStringLiteral("Exceptions")] = p.exceptions;
    if (!p.pacFile.isEmpty()) {
        port[QStringLiteral("Pacfile")] = QString::fromLatin1(p.pacFile);
    } else if (!p.pacUrl.isEmpty()) {
        port[QStringLiteral("NetworkProxyEnable")] = true;
        port[QStringLiteral("NetworkProxyURL")] = p.pacUrl;
    }
    if (!p.certs.isEmpty() && !*certsPlaced) {
        *certsPlaced = true;
        // The name EVE-OS reads since 13.x ...
        port[QStringLiteral("pubsub-large-ProxyCertPEM")] = p.certs;
        // ... and the one older releases read
        if (withLegacyCertKey)
            port[QStringLiteral("ProxyCertPEM")] = p.certs;
    }
}

QByteArray buildOverrideJsonImpl(const QVariantMap &config, bool withLegacyCertKey)
{
    const ProxySettings proxy = readProxy(config);
    const QString wifiSsid = str(config, "wifiSsid");
    const QString wifiPass = config.value(QStringLiteral("wifiPassword")).toString();

    QVariantList interfaces;
    const QVariantList given = config.value(QStringLiteral("interfaces")).toList();
    for (const QVariant &v : given) {
        const QVariantMap m = v.toMap();
        if (!str(m, "ifName").isEmpty())
            interfaces << m;
    }

    if (interfaces.isEmpty() && !proxy.active && wifiSsid.isEmpty())
        return QByteArray();

    // Proxy or WiFi without any interface chosen: keep the wired port that
    // EVE-OS would use on its own, so the device is not left with WiFi only.
    if (interfaces.isEmpty()) {
        QVariantMap eth0;
        eth0[QStringLiteral("ifName")] = QStringLiteral("eth0");
        eth0[QStringLiteral("mode")] = QStringLiteral("dhcp");
        eth0[QStringLiteral("isMgmt")] = true;
        interfaces << eth0;
    }

    static const QRegularExpression ifNameRe(QStringLiteral("^[A-Za-z0-9_.-]{1,15}$"));
    QJsonArray ports;
    QStringList seen;
    bool anyMgmt = false;
    bool certsPlaced = false;

    for (const QVariant &v : std::as_const(interfaces)) {
        const QVariantMap iface = v.toMap();
        const QString ifName = str(iface, "ifName");
        if (!ifNameRe.match(ifName).hasMatch())
            fail(tr("\"%1\" is not a valid interface name (at most 15 letters, digits, \".\", \"-\" or \"_\").").arg(ifName));
        if (seen.contains(ifName))
            fail(tr("The interface %1 is listed twice.").arg(ifName));
        seen << ifName;

        const bool isMgmt = iface.value(QStringLiteral("isMgmt"), true).toBool();
        QJsonObject port;
        port[QStringLiteral("IfName")] = ifName;
        port[QStringLiteral("Phylabel")] = ifName;
        port[QStringLiteral("Logicallabel")] = ifName;
        port[QStringLiteral("IsMgmt")] = isMgmt;
        // Explicit on every port: EVE-OS only fills this in when no port has it
        port[QStringLiteral("IsL3Port")] = true;
        addAddressing(port, iface, ifName);
        if (isMgmt)
            addProxy(port, proxy, withLegacyCertKey, &certsPlaced);
        ports.append(port);
        anyMgmt = anyMgmt || isMgmt;

        const QVariantList vlans = iface.value(QStringLiteral("vlans")).toList();
        for (const QVariant &vv : vlans) {
            const QVariantMap vlan = vv.toMap();
            const QString tagText = str(vlan, "tag");
            if (tagText.isEmpty())
                continue;
            bool ok = false;
            const int tag = tagText.toInt(&ok);
            if (!ok || tag < 1 || tag > 4094)
                fail(tr("%1: the VLAN tag \"%2\" must be a number from 1 to 4094.").arg(ifName, tagText));
            const QString vlanName = ifName + QLatin1Char('.') + QString::number(tag);
            if (vlanName.size() > 15)
                fail(tr("The VLAN name %1 is longer than the 15 characters Linux allows.").arg(vlanName));
            if (seen.contains(vlanName))
                fail(tr("VLAN %1 is listed twice on %2.").arg(tag).arg(ifName));
            seen << vlanName;

            const bool vlanMgmt = vlan.value(QStringLiteral("isMgmt"), false).toBool();
            QJsonObject vport;
            vport[QStringLiteral("IfName")] = vlanName;
            vport[QStringLiteral("Logicallabel")] = vlanName;
            vport[QStringLiteral("IsMgmt")] = vlanMgmt;
            vport[QStringLiteral("IsL3Port")] = true;
            vport[QStringLiteral("L2Type")] = L2LinkTypeVlan;
            QJsonObject l2;
            l2[QStringLiteral("ParentPort")] = ifName;
            l2[QStringLiteral("ID")] = tag;
            vport[QStringLiteral("VLAN")] = l2;
            addAddressing(vport, vlan, tr("VLAN %1 on %2").arg(tag).arg(ifName));
            if (vlanMgmt)
                addProxy(vport, proxy, withLegacyCertKey, &certsPlaced);
            ports.append(vport);
            anyMgmt = anyMgmt || vlanMgmt;
        }
    }

    if (!wifiSsid.isEmpty()) {
        if (seen.contains(QStringLiteral("wlan0")))
            fail(tr("wlan0 is the WiFi interface: remove it from the interface list, or clear the WiFi network name."));

        QJsonObject wifiEntry;
        wifiEntry[QStringLiteral("SSID")] = wifiSsid;
        wifiEntry[QStringLiteral("KeyScheme")] = WifiKeySchemeWpaPsk;
        if (!wifiPass.isEmpty())
            wifiEntry[QStringLiteral("Password")] = wifiPass;

        QJsonObject wirelessCfg;
        wirelessCfg[QStringLiteral("WType")] = WirelessTypeWifi;
        wirelessCfg[QStringLiteral("Wifi")] = QJsonArray{ wifiEntry };

        QJsonObject wifiPort;
        wifiPort[QStringLiteral("IfName")] = QStringLiteral("wlan0");
        wifiPort[QStringLiteral("Phylabel")] = QStringLiteral("wlan0");
        wifiPort[QStringLiteral("Logicallabel")] = QStringLiteral("wlan0");
        wifiPort[QStringLiteral("IsMgmt")] = true;
        wifiPort[QStringLiteral("IsL3Port")] = true;
        wifiPort[QStringLiteral("Dhcp")] = DhcpTypeClient;
        wifiPort[QStringLiteral("WirelessCfg")] = wirelessCfg;
        addProxy(wifiPort, proxy, withLegacyCertKey, &certsPlaced);
        ports.append(wifiPort);
        anyMgmt = true;
    }

    if (!anyMgmt)
        fail(tr("No interface is marked as management. The device needs at least one to reach the controller."));

    // No TimePriority on purpose: EVE-OS then treats this file as older than
    // anything the controller sends, so the controller's network settings win
    // as soon as the device can reach it.
    QJsonObject root;
    root[QStringLiteral("Version")] = 1;
    root[QStringLiteral("Ports")] = ports;
    return QJsonDocument(root).toJson(QJsonDocument::Compact);
}

// Values that end up on the kernel command line through grub.cfg: nothing
// that could end the quoted string or start a GRUB expansion.
QString checkedToken(const QString &value, const QString &what, const QString &allowed, const QString &allowedText)
{
    const QRegularExpression re(QStringLiteral("^[%1]+$").arg(allowed));
    if (!re.match(value).hasMatch())
        fail(tr("%1: \"%2\" may only contain %3.").arg(what, value, allowedText));
    return value;
}

QString checkedDiskList(const QString &value, const QString &what)
{
    QStringList disks;
    const QStringList parts = splitList(value);
    for (QString d : parts) {
        if (d.startsWith(QLatin1String("/dev/")))
            d = d.mid(5);
        disks << checkedToken(d, what, QStringLiteral("A-Za-z0-9_-"),
                              tr("Linux disk names such as sda or nvme0n1"));
    }
    return disks.join(QLatin1Char(','));
}

// GRUB commands that take one "name=value" option out of the platform
// defaults, so that the value set here is the only one on the command line.
// (The installer reads every occurrence, and two would be taken as one
// garbled disk name.)
QString grubStripOption(const QString &option)
{
    return QStringLiteral(
               "if regexp --set 1:evei_a --set 2:evei_b \"^(.*)%1=[^ ]*(.*)\" \"$dom0_platform_tweaks\"; then\n"
               "   set_global dom0_platform_tweaks \"$evei_a$evei_b\"\n"
               "fi\n").arg(option);
}

const char GrubBegin[] = "# >>> EVE Imager >>>";
const char GrubEnd[]   = "# <<< EVE Imager <<<";

// The 16 bytes of the EFI system partition type GUID as they are stored on disk
const unsigned char EfiSystemGuid[16] = { 0x28, 0x73, 0x2A, 0xC1, 0x1F, 0xF8, 0xD2, 0x11,
                                          0xBA, 0x4B, 0x00, 0xA0, 0xC9, 0x3E, 0xC9, 0x3B };

} // namespace

// ── Files ─────────────────────────────────────────────────────────────────────

namespace {

// True if `der` is one complete ASN.1 SEQUENCE, which is what a certificate is.
bool looksLikeDerCertificate(const QByteArray &der)
{
    if (der.size() < 64 || static_cast<unsigned char>(der.at(0)) != 0x30)
        return false;
    const unsigned char first = static_cast<unsigned char>(der.at(1));
    qint64 length = 0;
    int header = 2;
    if (first < 0x80) {
        length = first;
    } else {
        const int n = first & 0x7f;
        if (n < 1 || n > 4 || der.size() < 2 + n)
            return false;
        for (int i = 0; i < n; i++)
            length = (length << 8) | static_cast<unsigned char>(der.at(2 + i));
        header = 2 + n;
    }
    return header + length == der.size();
}

// A broken certificate would make EVE-OS reject the whole network
// configuration, so every block is decoded and checked.
void checkPemCertificates(const QByteArray &pem, const QString &what, const QString &path)
{
    static const QByteArray begin("-----BEGIN CERTIFICATE-----");
    static const QByteArray end("-----END CERTIFICATE-----");
    int pos = 0, count = 0;
    while ((pos = pem.indexOf(begin, pos)) >= 0) {
        const int bodyStart = pos + begin.size();
        const int bodyEnd = pem.indexOf(end, bodyStart);
        if (bodyEnd < 0)
            fail(tr("The %1 %2 is cut off: it has no END CERTIFICATE line.").arg(what, path));
        QByteArray body = pem.mid(bodyStart, bodyEnd - bodyStart);
        body.replace("\n", "").replace("\r", "").replace(" ", "").replace("\t", "");
        const auto decoded = QByteArray::fromBase64Encoding(body, QByteArray::AbortOnBase64DecodingErrors);
        if (!decoded || !looksLikeDerCertificate(*decoded))
            fail(tr("The %1 %2 is damaged: its contents are not a valid certificate.").arg(what, path));
        pos = bodyEnd + end.size();
        count++;
    }
    if (count == 0)
        fail(tr("The %1 %2 is not a certificate file (expected PEM or DER).").arg(what, path));
}

} // namespace

QByteArray EveConfigurator::readFileLimited(const QString &path, const QString &what, qint64 maxBytes)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        fail(tr("Cannot read the %1 %2: %3").arg(what, path, f.errorString()));
    if (f.size() > maxBytes)
        fail(tr("The %1 %2 is %3 KB; at most %4 KB fits.").arg(what, path)
                 .arg((f.size() + 1023) / 1024).arg(maxBytes / 1024));
    const QByteArray data = f.readAll();
    if (data.isEmpty())
        fail(tr("The %1 %2 is empty.").arg(what, path));
    return data;
}

QByteArray EveConfigurator::readCertificateAsPem(const QString &path, const QString &what)
{
    const QByteArray data = readFileLimited(path, what, 64 * 1024);

    if (data.contains("-----BEGIN CERTIFICATE-----")) {
        if (!data.contains("-----END CERTIFICATE-----"))
            fail(tr("The %1 %2 is cut off: it has no END CERTIFICATE line.").arg(what, path));
        if (data.contains("PRIVATE KEY-----"))
            fail(tr("The %1 %2 contains a private key. Choose the file that holds only the certificate.").arg(what, path));
        QByteArray pem = data;
        pem.replace("\r\n", "\n");
        if (!pem.endsWith('\n'))
            pem.append('\n');
        checkPemCertificates(pem, what, path);
        return pem;
    }
    if (data.contains("-----BEGIN "))
        fail(tr("The %1 %2 is not a certificate (it is another kind of PEM file).").arg(what, path));

    // Binary DER: an ASN.1 SEQUENCE. Wrap it as PEM.
    if (!looksLikeDerCertificate(data))
        fail(tr("The %1 %2 is not a certificate file (expected PEM or DER).").arg(what, path));
    const QByteArray b64 = data.toBase64();
    QByteArray pem("-----BEGIN CERTIFICATE-----\n");
    for (int i = 0; i < b64.size(); i += 64)
        pem.append(b64.mid(i, 64)).append('\n');
    pem.append("-----END CERTIFICATE-----\n");
    return pem;
}

// ── DevicePortConfig/override.json ────────────────────────────────────────────

QByteArray EveConfigurator::buildOverrideJson(const QVariantMap &config)
{
    // A bootstrap config replaces this file: EVE-OS ignores it when one is present.
    if (!str(config, "bootstrapConfigPath").isEmpty())
        return QByteArray();

    QByteArray json = buildOverrideJsonImpl(config, true);
    if (json.size() > MaxOverrideJsonBytes)
        json = buildOverrideJsonImpl(config, false);   // without the copy for old releases
    if (json.size() > MaxOverrideJsonBytes)
        fail(tr("The network settings take %1 KB, and EVE-OS accepts at most %2 KB. "
                "Use fewer or smaller proxy certificates, or a PAC URL in place of a PAC file.")
                 .arg((json.size() + 1023) / 1024).arg(MaxOverrideJsonBytes / 1024));
    return json;
}

// ── grub.cfg ──────────────────────────────────────────────────────────────────

QByteArray EveConfigurator::buildGrubBlock(const QVariantMap &config)
{
    const QString hardware = str(config, "hardware");
    QString installDisk = str(config, "installDisk");
    QString persistDisk = str(config, "persistDisk");
    const QString nukeDisks = str(config, "nukeDisks");
    const QString softSerial = str(config, "softSerial");
    const QString console = str(config, "console");
    const bool reboot = config.value(QStringLiteral("rebootAfterInstall"), false).toBool();
    const bool fr201Nvme = hardware == QLatin1String("fr201-nvme");

    QStringList strip;   // options to take out of the platform defaults
    QStringList args;    // options to add

    // An FR201 without eMMC installs on its NVMe drive, which the installer
    // sees as sdb (the USB stick being sda). EVE-OS's own default for the
    // FR201 is eMMC plus a persist partition on the NVMe drive.
    if (fr201Nvme) {
        if (installDisk.isEmpty())
            installDisk = QStringLiteral("sdb");
        strip << QStringLiteral("eve_install_disk") << QStringLiteral("eve_persist_disk");
        args << QStringLiteral("rootdelay=10");
    }
    if (!installDisk.isEmpty()) {
        strip << QStringLiteral("eve_install_disk");
        args << QStringLiteral("eve_install_disk=%1").arg(checkedDiskList(installDisk, tr("Install disk")));
    }
    if (!persistDisk.isEmpty()) {
        strip << QStringLiteral("eve_persist_disk");
        args << QStringLiteral("eve_persist_disk=%1").arg(checkedDiskList(persistDisk, tr("Persist disk")));
    }
    if (!nukeDisks.isEmpty()) {
        strip << QStringLiteral("eve_nuke_disks");
        args << QStringLiteral("eve_nuke_disks=%1").arg(checkedDiskList(nukeDisks, tr("Disks to wipe")));
    }
    if (!softSerial.isEmpty()) {
        args << QStringLiteral("eve_soft_serial=%1")
                    .arg(checkedToken(softSerial, tr("Soft serial number"), QStringLiteral("A-Za-z0-9._-"),
                                      tr("letters, digits, \".\", \"-\" and \"_\"")));
    }
    if (reboot)
        args << QStringLiteral("eve_reboot_after_install");

    QString consoleLine;
    if (console == QLatin1String("serial")) {
        // The last console= is the one the installer talks on; both get the messages.
        consoleLine = QStringLiteral("set_global dom0_console \"console=tty0 console=ttyS0,115200\"\n");
    } else if (console == QLatin1String("vga")) {
        consoleLine = QStringLiteral("set_global dom0_console \"console=ttyS0,115200 console=tty0\"\n");
    } else if (!console.isEmpty()) {
        fail(tr("Unknown console setting \"%1\".").arg(console));
    }

    if (args.isEmpty() && consoleLine.isEmpty())
        return QByteArray();

    strip.removeDuplicates();
    QString out;
    for (const QString &option : std::as_const(strip))
        out += grubStripOption(option);
    if (!args.isEmpty())
        out += QStringLiteral("set_global dom0_extra_args \"$dom0_extra_args %1\"\n").arg(args.join(QLatin1Char(' ')));
    out += consoleLine;
    return out.toUtf8();
}

QByteArray EveConfigurator::mergeGrubCfg(const QByteArray &existing, const QByteArray &block)
{
    // Keep what the image came with (it switches on the login prompt, for
    // one) and replace only the part written here earlier.
    QByteArray kept;
    bool inOurs = false;
    const QList<QByteArray> lines = existing.split('\n');
    for (int i = 0; i < lines.size(); i++) {
        const QByteArray &line = lines.at(i);
        if (line.trimmed() == GrubBegin) { inOurs = true; continue; }
        if (line.trimmed() == GrubEnd)   { inOurs = false; continue; }
        if (inOurs)
            continue;
        if (i == lines.size() - 1 && line.isEmpty())
            break;                                   // the split's empty tail
        kept.append(line).append('\n');
    }
    if (block.isEmpty())
        return kept;
    return kept + GrubBegin + '\n' + block + GrubEnd + '\n';
}

// ── config.txt (OnLogic FR201) ────────────────────────────────────────────────

QByteArray EveConfigurator::patchConfigTxtForFr201(const QByteArray &configTxt)
{
    // From the EVE-OS README, "FR201 boot configuration": switch off the TPM
    // overlay of the generic Compute Module 4 and include the FR201 settings.
    QByteArray out;
    bool includeFound = false;
    const QList<QByteArray> lines = configTxt.split('\n');
    for (int i = 0; i < lines.size(); i++) {
        QByteArray line = lines.at(i);
        const QByteArray bare = line.trimmed();
        if (bare.startsWith("dtoverlay=bcm2711-spi-tpm-slb9670")) {
            line = "#" + line;
        } else if (bare == "#include fr201.txt" || bare == "# include fr201.txt") {
            line = line.endsWith('\r') ? QByteArray("include fr201.txt\r") : QByteArray("include fr201.txt");
            includeFound = true;
        } else if (bare == "include fr201.txt") {
            includeFound = true;
        }
        out.append(line);
        if (i < lines.size() - 1)
            out.append('\n');
    }
    if (!includeFound)
        fail(tr("This EVE-OS image has no OnLogic FR201 support in its boot files "
                "(EVE-OS 14.5 and later have it). Choose a newer release, or set Hardware back to Generic."));
    return out;
}

// ── Partitions ────────────────────────────────────────────────────────────────

DeviceWrapperFatPartition *EveConfigurator::findPartition(DeviceWrapper &dw, bool efiSystem)
{
    struct gpt_header gpt;
    dw.pread(reinterpret_cast<char *>(&gpt), sizeof(gpt), 512); // LBA 1

    if (strncmp(gpt.Signature, "EFI PART", 8) != 0 || gpt.MyLBA != 1) {
        qDebug() << "EveConfigurator: no GPT header found";
        return nullptr;
    }

    // A sane table has at most a few hundred entries
    const quint32 entries = qMin<quint32>(gpt.NumberOfPartitionEntries, 256);
    for (quint32 i = 0; i < entries; i++) {
        struct gpt_partition part;
        quint64 offset = gpt.PartitionEntryLBA * 512
                         + static_cast<quint64>(gpt.SizeOfPartitionEntry) * i;
        dw.pread(reinterpret_cast<char *>(&part), sizeof(part), offset);

        bool empty = true;
        for (int b = 0; b < 16; b++) {
            if (part.PartitionTypeGuid[b] != 0) { empty = false; break; }
        }
        if (empty)
            continue;

        // PartitionName is UTF-16LE, 72 bytes = up to 36 characters
        QString name = QString::fromUtf16(
            reinterpret_cast<const char16_t *>(part.PartitionName), 36);
        int end = name.indexOf(QChar(0));
        if (end >= 0)
            name.truncate(end);

        const bool match = efiSystem
            ? memcmp(part.PartitionTypeGuid, EfiSystemGuid, 16) == 0
            : name == QLatin1String("CONFIG");
        if (match) {
            quint64 partStart = part.StartingLBA * 512;
            quint64 partLen   = (part.EndingLBA - part.StartingLBA + 1) * 512;
            qDebug() << "EveConfigurator: found" << (efiSystem ? "EFI system" : "CONFIG")
                     << "partition at LBA" << part.StartingLBA << "len" << partLen;
            return new DeviceWrapperFatPartition(&dw, partStart, partLen);
        }
    }

    qDebug() << "EveConfigurator:" << (efiSystem ? "EFI system" : "CONFIG") << "partition not found in GPT";
    return nullptr;
}

// ── Entry points ──────────────────────────────────────────────────────────────

bool EveConfigurator::hasAnything(const QVariantMap &config)
{
    for (const char *key : { "controllerUrl", "rootCertPath", "onboardCertPath", "onboardKeyPath",
                             "authorizedKeys", "wifiSsid", "installDisk", "persistDisk", "nukeDisks",
                             "softSerial", "console", "hardware", "bootstrapConfigPath" }) {
        if (!str(config, key).isEmpty())
            return true;
    }
    if (config.value(QStringLiteral("proxyEnabled")).toBool()
        || config.value(QStringLiteral("rebootAfterInstall")).toBool())
        return true;
    const QVariantList interfaces = config.value(QStringLiteral("interfaces")).toList();
    for (const QVariant &v : interfaces) {
        if (!str(v.toMap(), "ifName").isEmpty())
            return true;
    }
    return false;
}

namespace {

// Everything that is decided before a drive is touched
struct Prepared {
    QString controllerUrl;
    QByteArray rootCert, onboardCert, onboardKey, authorizedKeys;
    QByteArray overrideJson, grubBlock, bootstrap;
    bool fr201 = false;
};

} // namespace

static Prepared prepare(const QVariantMap &config)
{
    Prepared p;

    p.controllerUrl = str(config, "controllerUrl");
    if (!p.controllerUrl.isEmpty()) {
        // A host name with an optional port; people paste URLs, so take those apart
        QString host = p.controllerUrl;
        if (host.contains(QLatin1String("://")))
            host = host.mid(host.indexOf(QLatin1String("://")) + 3);
        while (host.endsWith(QLatin1Char('/')))
            host.chop(1);
        static const QRegularExpression hostRe(QStringLiteral("^[A-Za-z0-9.-]+(:[0-9]{1,5})?$"));
        if (!hostRe.match(host).hasMatch())
            fail(tr("Controller: \"%1\" is not a host name, for example zedcloud.zededa.net.").arg(p.controllerUrl));
        p.controllerUrl = host;
    }

    const QString rootCertPath = str(config, "rootCertPath");
    if (!rootCertPath.isEmpty())
        p.rootCert = EveConfigurator::readCertificateAsPem(rootCertPath, tr("controller root certificate"));

    const QString onboardCertPath = str(config, "onboardCertPath");
    const QString onboardKeyPath = str(config, "onboardKeyPath");
    if (onboardCertPath.isEmpty() != onboardKeyPath.isEmpty())
        fail(tr("The onboarding certificate and its key belong together: choose both, or neither."));
    if (!onboardCertPath.isEmpty()) {
        p.onboardCert = EveConfigurator::readCertificateAsPem(onboardCertPath, tr("onboarding certificate"));
        QFile f(onboardKeyPath);
        if (!f.open(QIODevice::ReadOnly))
            fail(tr("Cannot read the onboarding key %1: %2").arg(onboardKeyPath, f.errorString()));
        p.onboardKey = f.read(64 * 1024);
        if (!p.onboardKey.contains("PRIVATE KEY-----"))
            fail(tr("The onboarding key %1 is not a PEM private key.").arg(onboardKeyPath));
    }

    const QString keys = str(config, "authorizedKeys");
    if (!keys.isEmpty()) {
        // EVE-OS accepts "keytype base64 comment" lines only, no options
        static const QRegularExpression keyRe(QStringLiteral("^(ssh-[a-z0-9-]+|ecdsa-sha2-[a-z0-9-]+|sk-[a-z0-9@.-]+) [A-Za-z0-9+/=]+( .*)?$"));
        QStringList lines;
        const QStringList given = keys.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        for (const QString &l : given) {
            const QString line = l.trimmed();
            if (line.isEmpty())
                continue;
            if (!keyRe.match(line).hasMatch())
                fail(tr("SSH key: each line must be a public key such as \"ssh-ed25519 AAAA… name\", without options in front."));
            lines << line;
        }
        p.authorizedKeys = lines.join(QLatin1Char('\n')).toUtf8() + '\n';
    }

    const QString bootstrapPath = str(config, "bootstrapConfigPath");
    if (!bootstrapPath.isEmpty()) {
        QFile f(bootstrapPath);
        if (!f.open(QIODevice::ReadOnly))
            fail(tr("Cannot read the bootstrap config %1: %2").arg(bootstrapPath, f.errorString()));
        if (f.size() > 256 * 1024)
            fail(tr("The bootstrap config %1 is too large for the configuration partition.").arg(bootstrapPath));
        p.bootstrap = f.readAll();
        if (p.bootstrap.isEmpty())
            fail(tr("The bootstrap config %1 is empty.").arg(bootstrapPath));
    }

    p.overrideJson = EveConfigurator::buildOverrideJson(config);
    p.grubBlock = EveConfigurator::buildGrubBlock(config);

    const QString hardware = str(config, "hardware");
    if (hardware == QLatin1String("fr201") || hardware == QLatin1String("fr201-nvme"))
        p.fr201 = true;
    else if (!hardware.isEmpty())
        fail(tr("Unknown hardware setting \"%1\".").arg(hardware));

    return p;
}

QString EveConfigurator::validate(const QVariantMap &config)
{
    try {
        prepare(config);
    } catch (const std::runtime_error &e) {
        return QString::fromStdString(e.what());
    }
    return QString();
}

bool EveConfigurator::apply(DeviceWrapper &dw, const QVariantMap &config)
{
    if (!hasAnything(config))
        return false;

    const Prepared p = prepare(config);
    bool anyWritten = false;

    const bool needsConfigPartition = !p.controllerUrl.isEmpty() || !p.rootCert.isEmpty() || !p.onboardCert.isEmpty()
                                      || !p.authorizedKeys.isEmpty() || !p.overrideJson.isEmpty()
                                      || !p.grubBlock.isEmpty() || !p.bootstrap.isEmpty();
    if (needsConfigPartition) {
        std::unique_ptr<DeviceWrapperFatPartition> fat(findPartition(dw, false));
        if (!fat)
            fail(tr("The image was written, but it has no CONFIG partition, so the configuration could not be added. "
                    "EVE-OS installer images in .raw format have one."));

        if (!p.controllerUrl.isEmpty()) {
            fat->writeFile(QStringLiteral("server"), p.controllerUrl.toUtf8() + '\n');
            qDebug() << "EveConfigurator: wrote server =" << p.controllerUrl;
        }
        if (!p.rootCert.isEmpty()) {
            fat->writeFile(QStringLiteral("root-certificate.pem"), p.rootCert);
            qDebug() << "EveConfigurator: wrote root-certificate.pem";
        }
        if (!p.onboardCert.isEmpty()) {
            fat->writeFile(QStringLiteral("onboard.cert.pem"), p.onboardCert);
            fat->writeFile(QStringLiteral("onboard.key.pem"), p.onboardKey);
            qDebug() << "EveConfigurator: wrote onboard.cert.pem and onboard.key.pem";
        }
        if (!p.authorizedKeys.isEmpty()) {
            fat->writeFile(QStringLiteral("authorized_keys"), p.authorizedKeys);
            qDebug() << "EveConfigurator: wrote authorized_keys";
        }
        if (!p.bootstrap.isEmpty()) {
            fat->writeFile(QStringLiteral("bootstrap-config.pb"), p.bootstrap);
            qDebug() << "EveConfigurator: wrote bootstrap-config.pb," << p.bootstrap.size() << "bytes";
        }
        if (!p.overrideJson.isEmpty()) {
            fat->writeFile(QStringLiteral("DevicePortConfig/override.json"), p.overrideJson);
            qDebug() << "EveConfigurator: wrote DevicePortConfig/override.json," << p.overrideJson.size() << "bytes";
        }
        if (!p.grubBlock.isEmpty()) {
            QByteArray existing;
            if (fat->fileExists(QStringLiteral("grub.cfg")))
                existing = fat->readFile(QStringLiteral("grub.cfg"));
            fat->writeFile(QStringLiteral("grub.cfg"), mergeGrubCfg(existing, p.grubBlock));
            qDebug() << "EveConfigurator: wrote grub.cfg";
        }
        anyWritten = true;
    }

    if (p.fr201) {
        std::unique_ptr<DeviceWrapperFatPartition> efi(findPartition(dw, true));
        if (!efi || !efi->fileExists(QStringLiteral("config.txt")))
            fail(tr("The image was written, but the OnLogic FR201 settings could not be applied: "
                    "it has no config.txt on its boot partition. FR201 needs an arm64 image."));
        if (!efi->fileExists(QStringLiteral("fr201.txt")))
            fail(tr("The image was written, but it has no OnLogic FR201 support in its boot files "
                    "(EVE-OS 14.5 and later have it). Choose a newer release, or set Hardware back to Generic."));
        const QByteArray before = efi->readFile(QStringLiteral("config.txt"));
        const QByteArray after = patchConfigTxtForFr201(before);
        if (after != before)
            efi->writeFile(QStringLiteral("config.txt"), after);
        qDebug() << "EveConfigurator: config.txt set up for OnLogic FR201";
        anyWritten = true;
    }

    return anyWritten;
}
