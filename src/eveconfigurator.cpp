/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 ZEDEDA, Inc.
 */

#include "eveconfigurator.h"
#include "devicewrapper.h"
#include "devicewrapperfatpartition.h"
#include "devicewrapperstructs.h"

#include <QDebug>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QString>

// ── GPT partition scan ────────────────────────────────────────────────────────

DeviceWrapperFatPartition *EveConfigurator::findConfigPartition(DeviceWrapper &dw)
{
    struct gpt_header gpt;
    dw.pread(reinterpret_cast<char *>(&gpt), sizeof(gpt), 512); // LBA 1

    if (strncmp(gpt.Signature, "EFI PART", 8) != 0 || gpt.MyLBA != 1) {
        qDebug() << "EveConfigurator: no GPT header found";
        return nullptr;
    }

    for (quint32 i = 0; i < gpt.NumberOfPartitionEntries; i++) {
        struct gpt_partition part;
        quint64 offset = gpt.PartitionEntryLBA * 512
                         + static_cast<quint64>(gpt.SizeOfPartitionEntry) * i;
        dw.pread(reinterpret_cast<char *>(&part), sizeof(part), offset);

        // Skip empty entries (zero type GUID)
        bool empty = true;
        for (int b = 0; b < 16; b++) {
            if (part.PartitionTypeGuid[b] != 0) { empty = false; break; }
        }
        if (empty)
            continue;

        // PartitionName is UTF-16LE, 72 bytes = up to 36 characters
        QString name = QString::fromUtf16(
            reinterpret_cast<const char16_t *>(part.PartitionName), 36);
        // Trim trailing null characters
        int end = name.indexOf(QChar(0));
        if (end >= 0)
            name.truncate(end);

        if (name == QLatin1String("CONFIG")) {
            quint64 partStart = part.StartingLBA * 512;
            quint64 partLen   = (part.EndingLBA - part.StartingLBA + 1) * 512;
            qDebug() << "EveConfigurator: found CONFIG partition at LBA"
                     << part.StartingLBA << "len" << partLen;
            return new DeviceWrapperFatPartition(&dw, partStart, partLen);
        }
    }

    qDebug() << "EveConfigurator: CONFIG partition not found in GPT";
    return nullptr;
}

// ── JSON generation ───────────────────────────────────────────────────────────

QByteArray EveConfigurator::buildOverrideJson(const QVariantMap &config)
{
    QString networkMode = config.value("networkMode", "dhcp").toString();
    QString proxyUrl    = config.value("proxyUrl").toString().trimmed();

    // Only needed for static IP or proxy settings
    if (networkMode != QLatin1String("static") && proxyUrl.isEmpty())
        return QByteArray();

    QJsonObject port;
    port["Free"]   = true;
    port["IfName"] = "eth0";
    port["Name"]   = "Management";
    port["IsMgmt"] = true;

    if (networkMode == QLatin1String("static")) {
        port["Dhcp"]       = 1;
        port["AddrSubnet"] = config.value("staticIp").toString().trimmed();
        port["Gateway"]    = config.value("gateway").toString().trimmed();

        QString dns = config.value("dns").toString().trimmed();
        if (!dns.isEmpty()) {
            QJsonArray dnsArr;
            const QStringList parts = dns.split(QLatin1Char(','));
            for (const QString &s : parts) {
                QString trimmed = s.trimmed();
                if (!trimmed.isEmpty())
                    dnsArr.append(trimmed);
            }
            port["DnsServers"] = dnsArr;
        } else {
            port["DnsServers"] = QJsonValue::Null;
        }
    } else {
        // DHCP with proxy
        port["Dhcp"] = 4;
    }

    if (!proxyUrl.isEmpty()) {
        port["NetworkProxyEnable"] = true;
        port["NetworkProxyURL"]    = proxyUrl;
    } else {
        port["NetworkProxyEnable"] = false;
        port["NetworkProxyURL"]    = QString();
    }

    QJsonObject root;
    root["Version"] = 1;
    root["Ports"]   = QJsonArray{ port };

    return QJsonDocument(root).toJson(QJsonDocument::Indented);
}

// ── Main entry point ──────────────────────────────────────────────────────────

bool EveConfigurator::apply(DeviceWrapper &dw, const QVariantMap &config)
{
    bool anyWritten = false;

    DeviceWrapperFatPartition *fat = findConfigPartition(dw);
    if (!fat) {
        qWarning() << "EveConfigurator::apply: CONFIG partition not found — skipping";
        return false;
    }

    // `server` file — controller URL (plain text, newline terminated)
    QString controllerUrl = config.value("controllerUrl").toString().trimmed();
    if (!controllerUrl.isEmpty()) {
        QByteArray content = controllerUrl.toUtf8() + '\n';
        fat->writeFile("server", content);
        qDebug() << "EveConfigurator: wrote server =" << controllerUrl;
        anyWritten = true;
    }

    // `DevicePortConfig/override.json` — network configuration
    QByteArray overrideJson = buildOverrideJson(config);
    if (!overrideJson.isEmpty()) {
        fat->writeFile("DevicePortConfig/override.json", overrideJson);
        qDebug() << "EveConfigurator: wrote DevicePortConfig/override.json";
        anyWritten = true;
    }

    // `onboard.cert.pem` — onboarding certificate
    QString certPath = config.value("onboardCertPath").toString().trimmed();
    if (!certPath.isEmpty()) {
        QFile f(certPath);
        if (f.open(QIODevice::ReadOnly)) {
            fat->writeFile("onboard.cert.pem", f.readAll());
            qDebug() << "EveConfigurator: wrote onboard.cert.pem from" << certPath;
            anyWritten = true;
        } else {
            qWarning() << "EveConfigurator: cannot read cert file" << certPath;
        }
    }

    // `onboard.key.pem` — onboarding private key
    QString keyPath = config.value("onboardKeyPath").toString().trimmed();
    if (!keyPath.isEmpty()) {
        QFile f(keyPath);
        if (f.open(QIODevice::ReadOnly)) {
            fat->writeFile("onboard.key.pem", f.readAll());
            qDebug() << "EveConfigurator: wrote onboard.key.pem from" << keyPath;
            anyWritten = true;
        } else {
            qWarning() << "EveConfigurator: cannot read key file" << keyPath;
        }
    }

    // `soft_serial` — device serial number
    QString serial = config.value("deviceSerial").toString().trimmed();
    if (!serial.isEmpty()) {
        fat->writeFile("soft_serial", serial.toUtf8() + '\n');
        qDebug() << "EveConfigurator: wrote soft_serial =" << serial;
        anyWritten = true;
    }

    delete fat;
    return anyWritten;
}
