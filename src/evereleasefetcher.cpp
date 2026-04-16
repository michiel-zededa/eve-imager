/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 ZEDEDA, Inc.
 */

#include "evereleasefetcher.h"
#include "curlfetcher.h"

#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

static const char *RELEASES_URL =
    "https://api.github.com/repos/lf-edge/eve/releases?per_page=50";

// ── Constructor ───────────────────────────────────────────────────────────────

EveReleaseFetcher::EveReleaseFetcher(QObject *parent)
    : QObject(parent)
{
    _statusMessage = tr("No releases loaded");
}

// ── Private helpers ───────────────────────────────────────────────────────────

void EveReleaseFetcher::setLoading(bool v)
{
    if (_loading == v) return;
    _loading = v;
    emit loadingChanged();
}

void EveReleaseFetcher::setStatusMessage(const QString &msg)
{
    if (_statusMessage == msg) return;
    _statusMessage = msg;
    emit statusMessageChanged();
}

// ── Network fetch ─────────────────────────────────────────────────────────────

void EveReleaseFetcher::fetchReleases()
{
    if (_loading) return;     // Don't overlap fetches

    setLoading(true);
    setStatusMessage(tr("Loading releases…"));
    _releases.clear();

    auto *fetcher = new CurlFetcher(this);
    connect(fetcher, &CurlFetcher::finished, this, &EveReleaseFetcher::onFetchFinished);
    connect(fetcher, &CurlFetcher::error,    this, &EveReleaseFetcher::onFetchError);
    fetcher->fetch(QUrl(QLatin1String(RELEASES_URL)));
}

void EveReleaseFetcher::onFetchFinished(const QByteArray &data,
                                        const QUrl & /*url*/,
                                        const QUrl & /*effectiveUrl*/)
{
    parseReleases(data);
    setLoading(false);

    if (_releases.isEmpty()) {
        setStatusMessage(tr("No EVE OS releases found"));
        emit fetchFailed(tr("No installer assets found in the EVE OS GitHub releases"));
    } else {
        setStatusMessage(tr("Ready — %1 releases available").arg(_releases.size()));
        emit releasesReady();
    }
}

void EveReleaseFetcher::onFetchError(const QString &errorMessage, const QUrl & /*url*/)
{
    setLoading(false);
    setStatusMessage(tr("Error: %1").arg(errorMessage));
    qWarning() << "EveReleaseFetcher: fetch error:" << errorMessage;
    emit fetchFailed(errorMessage);
}

// ── JSON parsing ──────────────────────────────────────────────────────────────

void EveReleaseFetcher::parseReleases(const QByteArray &json)
{
    QJsonParseError err;
    QJsonDocument doc = QJsonDocument::fromJson(json, &err);
    if (err.error != QJsonParseError::NoError) {
        qWarning() << "EveReleaseFetcher: JSON parse error:" << err.errorString();
        return;
    }

    if (!doc.isArray()) {
        qWarning() << "EveReleaseFetcher: expected JSON array";
        return;
    }

    const QJsonArray releases = doc.array();
    for (const QJsonValue &rv : releases) {
        QJsonObject ro = rv.toObject();

        // Skip drafts and pre-releases
        if (ro["draft"].toBool() || ro["prerelease"].toBool())
            continue;

        QString version = ro["tag_name"].toString().trimmed();
        if (version.isEmpty())
            continue;

        // Collect installer assets (.raw preferred, .iso as fallback)
        // First pass: collect all candidates, then deduplicate preferring .raw over .iso
        QList<AssetInfo> assets;
        const QJsonArray assetArr = ro["assets"].toArray();
        for (const QJsonValue &av : assetArr) {
            QJsonObject ao = av.toObject();
            QString name = ao["name"].toString();

            // Accept .installer.raw or .installer.iso
            bool isRaw = name.endsWith(QLatin1String(".installer.raw"));
            bool isIso = !isRaw && name.endsWith(QLatin1String(".installer.iso"));
            if (!isRaw && !isIso)
                continue;

            // Format: {arch}.{hv}.{platform}.installer.{raw|iso}
            int suffixLen = isRaw
                            ? QStringLiteral(".installer.raw").length()
                            : QStringLiteral(".installer.iso").length();
            QString prefix = name.chopped(suffixLen);
            QStringList parts = prefix.split(QLatin1Char('.'));
            if (parts.size() < 3)
                continue;

            AssetInfo asset;
            asset.arch        = parts[0];
            asset.hypervisor  = parts[1];
            asset.platform    = parts.mid(2).join(QLatin1Char('.'));
            asset.downloadUrl = ao["browser_download_url"].toString();
            asset.size        = ao["size"].toVariant().toLongLong();
            asset.isIso       = isIso;

            // Prefer .raw over .iso: if we already have a .raw for this combo, skip the .iso
            bool alreadyHaveRaw = false;
            for (const AssetInfo &existing : assets) {
                if (existing.arch == asset.arch
                    && existing.hypervisor == asset.hypervisor
                    && existing.platform == asset.platform
                    && !existing.isIso) {
                    alreadyHaveRaw = true;
                    break;
                }
            }
            if (alreadyHaveRaw)
                continue;

            // If we have an existing .iso entry for this combo and this is a .raw, replace it
            if (isRaw) {
                for (int i = 0; i < assets.size(); ++i) {
                    if (assets[i].arch == asset.arch
                        && assets[i].hypervisor == asset.hypervisor
                        && assets[i].platform == asset.platform) {
                        assets[i] = asset;  // replace iso with raw
                        goto nextAsset;
                    }
                }
            }

            assets.append(asset);
            nextAsset:;
        }

        if (assets.isEmpty())
            continue;   // No installer images for this release — skip

        ReleaseInfo rel;
        rel.version = version;
        rel.assets  = assets;
        _releases.append(rel);
    }

    qDebug() << "EveReleaseFetcher: parsed" << _releases.size() << "releases";
}

// ── Property accessors ────────────────────────────────────────────────────────

QStringList EveReleaseFetcher::versions() const
{
    QStringList result;
    result.reserve(_releases.size());
    for (const ReleaseInfo &r : _releases)
        result.append(r.version);
    return result;
}

// ── Cascading combo helpers ───────────────────────────────────────────────────

QStringList EveReleaseFetcher::archesForVersion(const QString &version) const
{
    QStringList result;
    for (const ReleaseInfo &r : _releases) {
        if (r.version != version) continue;
        for (const AssetInfo &a : r.assets)
            if (!result.contains(a.arch))
                result.append(a.arch);
        break;
    }
    return result;
}

QStringList EveReleaseFetcher::hypervisorsFor(const QString &version,
                                              const QString &arch) const
{
    QStringList result;
    for (const ReleaseInfo &r : _releases) {
        if (r.version != version) continue;
        for (const AssetInfo &a : r.assets)
            if (a.arch == arch && !result.contains(a.hypervisor))
                result.append(a.hypervisor);
        break;
    }
    return result;
}

QStringList EveReleaseFetcher::platformsFor(const QString &version,
                                            const QString &arch,
                                            const QString &hypervisor) const
{
    QStringList result;
    for (const ReleaseInfo &r : _releases) {
        if (r.version != version) continue;
        for (const AssetInfo &a : r.assets)
            if (a.arch == arch && a.hypervisor == hypervisor
                && !result.contains(a.platform))
                result.append(a.platform);
        break;
    }
    return result;
}

// ── Asset lookup ──────────────────────────────────────────────────────────────

const EveReleaseFetcher::AssetInfo *
EveReleaseFetcher::findAsset(const QString &version,
                             const QString &arch,
                             const QString &hypervisor,
                             const QString &platform) const
{
    for (const ReleaseInfo &r : _releases) {
        if (r.version != version) continue;
        for (const AssetInfo &a : r.assets)
            if (a.arch == arch && a.hypervisor == hypervisor && a.platform == platform)
                return &a;
        break;
    }
    return nullptr;
}

QString EveReleaseFetcher::downloadUrl(const QString &version,
                                       const QString &arch,
                                       const QString &hypervisor,
                                       const QString &platform) const
{
    const AssetInfo *a = findAsset(version, arch, hypervisor, platform);
    return a ? a->downloadUrl : QString();
}

qint64 EveReleaseFetcher::downloadSize(const QString &version,
                                       const QString &arch,
                                       const QString &hypervisor,
                                       const QString &platform) const
{
    const AssetInfo *a = findAsset(version, arch, hypervisor, platform);
    return a ? a->size : 0;
}

bool EveReleaseFetcher::isIsoAsset(const QString &version,
                                   const QString &arch,
                                   const QString &hypervisor,
                                   const QString &platform) const
{
    const AssetInfo *a = findAsset(version, arch, hypervisor, platform);
    return a ? a->isIso : false;
}
