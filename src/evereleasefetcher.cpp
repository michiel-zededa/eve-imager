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
#include <algorithm>

// GitHub API: 100 releases per page (maximum). EVE has 260+ releases so we
// paginate to ensure all major-version LTS releases are visible.
static const char *RELEASES_URL_TEMPLATE =
    "https://api.github.com/repos/lf-edge/eve/releases?per_page=100&page=%1";

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

void EveReleaseFetcher::setFetchFailed(bool v)
{
    if (_fetchFailed == v) return;
    _fetchFailed = v;
    emit fetchFailedChanged();
}

void EveReleaseFetcher::setStatusMessage(const QString &msg)
{
    if (_statusMessage == msg) return;
    _statusMessage = msg;
    emit statusMessageChanged();
}

// ── showNonLts property ───────────────────────────────────────────────────────

void EveReleaseFetcher::setShowNonLts(bool v)
{
    if (_showNonLts == v) return;
    _showNonLts = v;
    emit showNonLtsChanged();
    // Re-emit releasesReady so the QML version combo model is refreshed
    if (!_releases.isEmpty())
        emit releasesReady();
}

// ── Network fetch ─────────────────────────────────────────────────────────────

void EveReleaseFetcher::fetchReleases()
{
    if (_loading) return;     // Don't overlap fetches

    setLoading(true);
    setFetchFailed(false);
    setStatusMessage(tr("Loading releases…"));
    _releases.clear();
    fetchPage(1);
}

void EveReleaseFetcher::fetchPage(int page)
{
    _currentPage = page;
    QString url = QString::fromLatin1(RELEASES_URL_TEMPLATE).arg(page);
    auto *fetcher = new CurlFetcher(this);
    connect(fetcher, &CurlFetcher::finished, this, &EveReleaseFetcher::onFetchFinished);
    connect(fetcher, &CurlFetcher::error,    this, &EveReleaseFetcher::onFetchError);
    fetcher->fetch(QUrl(url));
}

void EveReleaseFetcher::onFetchFinished(const QByteArray &data,
                                        const QUrl & /*url*/,
                                        const QUrl & /*effectiveUrl*/)
{
    int countBefore = _releases.size();
    int pageEntries = parseReleases(data);  // raw JSON entries on this page
    Q_UNUSED(countBefore)

    // Continue if the page was non-empty AND we haven't reached the limit.
    // Use raw entry count (not filtered asset count) so a page full of
    // non-.raw releases (e.g. older .img-only releases) doesn't stop pagination.
    if (pageEntries > 0 && _currentPage < MAX_PAGES) {
        setStatusMessage(tr("Loading releases… (page %1)").arg(_currentPage + 1));
        fetchPage(_currentPage + 1);
        return;
    }

    // All pages fetched — sort everything newest-first and notify
    std::sort(_releases.begin(), _releases.end(),
              [](const ReleaseInfo &a, const ReleaseInfo &b) {
                  return a.publishedAt > b.publishedAt;
              });

    setLoading(false);

    if (_releases.isEmpty()) {
        setFetchFailed(true);
        setStatusMessage(tr("No EVE OS releases found"));
        emit fetchFailed(tr("No installer assets found in the EVE OS GitHub releases"));
    } else {
        setFetchFailed(false);
        setStatusMessage(tr("Ready — %1 releases available").arg(_releases.size()));
        emit releasesReady();
    }
}

void EveReleaseFetcher::onFetchError(const QString &errorMessage, const QUrl & /*url*/)
{
    setLoading(false);
    setFetchFailed(true);
    setStatusMessage(tr("Error: %1").arg(errorMessage));
    qWarning() << "EveReleaseFetcher: fetch error:" << errorMessage;
    emit fetchFailed(errorMessage);
}

// ── JSON parsing ──────────────────────────────────────────────────────────────

int EveReleaseFetcher::parseReleases(const QByteArray &json)
{
    QJsonParseError err;
    QJsonDocument doc = QJsonDocument::fromJson(json, &err);
    if (err.error != QJsonParseError::NoError) {
        qWarning() << "EveReleaseFetcher: JSON parse error:" << err.errorString();
        return 0;
    }

    if (!doc.isArray()) {
        qWarning() << "EveReleaseFetcher: expected JSON array";
        return 0;
    }

    const QJsonArray releases = doc.array();
    int entryCount = releases.size();
    for (const QJsonValue &rv : releases) {
        QJsonObject ro = rv.toObject();

        // Skip drafts and pre-releases (RCs, betas).
        // Note: if the EVE team marks a stable LTS release as prerelease=true by
        // mistake, it will be hidden here. Ask them to fix the release on GitHub.
        if (ro["draft"].toBool() || ro["prerelease"].toBool())
            continue;

        QString tagName = ro["tag_name"].toString().trimmed();
        if (tagName.isEmpty())
            continue;

        // Detect LTS:
        // 1. Explicit: tag or release title contains "lts"
        // 2. Heuristic: even minor version (X.Y.Z where Y is even).
        //    EVE follows the common convention that even minor = LTS,
        //    odd minor = current/edge (e.g. 12.0.x, 12.2.x are LTS;
        //    12.1.x, 12.3.x are current releases).
        QString releaseName = ro["name"].toString();
        bool isLts = tagName.contains(QLatin1String("lts"), Qt::CaseInsensitive)
                  || releaseName.contains(QLatin1String("lts"), Qt::CaseInsensitive);
        if (!isLts) {
            // Strip leading 'v' prefix if present, then parse X.Y.Z
            QString ver = tagName;
            if (ver.startsWith(QLatin1Char('v')) || ver.startsWith(QLatin1Char('V')))
                ver = ver.mid(1);
            const QStringList parts = ver.split(QLatin1Char('.'));
            if (parts.size() >= 2) {
                bool ok = false;
                int minor = parts.at(1).toInt(&ok);
                if (ok && (minor % 2 == 0))
                    isLts = true;
            }
        }

        // Parse publication date for chronological sorting
        QDateTime publishedAt = QDateTime::fromString(
            ro["published_at"].toString(), Qt::ISODate);

        // Collect installer assets (.raw preferred, .iso as fallback)
        QList<AssetInfo> assets;
        const QJsonArray assetArr = ro["assets"].toArray();
        for (const QJsonValue &av : assetArr) {
            QJsonObject ao = av.toObject();
            QString name = ao["name"].toString();

            // Accept installer assets in all supported formats:
            //   .installer.raw      — uncompressed raw image (preferred)
            //   .installer.raw.zst  — zstd-compressed raw (libarchive decompresses on the fly)
            //   .installer.img      — gzip-compressed raw image used by older EVE releases (≤12.x);
            //                         same disk image content as .raw, libarchive decompresses it
            //   .installer.iso      — ISO image (no config-partition customization)
            // Rejected: .installer-net.tar (network installer archive, not USB-writable)
            bool isRawZst = name.endsWith(QLatin1String(".installer.raw.zst"));
            bool isRaw    = !isRawZst && (name.endsWith(QLatin1String(".installer.raw"))
                                       || name.endsWith(QLatin1String(".installer.img")));
            bool isIso    = !isRaw && !isRawZst && name.endsWith(QLatin1String(".installer.iso"));
            if (!isRaw && !isRawZst && !isIso)
                continue;

            // Determine suffix length to strip to get "{arch}[.{hv}.{platform}]" prefix
            int suffixLen;
            if (isRawZst)  suffixLen = QStringLiteral(".installer.raw.zst").length();
            else if (isIso) suffixLen = QStringLiteral(".installer.iso").length();
            else if (name.endsWith(QLatin1String(".installer.img")))
                           suffixLen = QStringLiteral(".installer.img").length();
            else           suffixLen = QStringLiteral(".installer.raw").length();

            // Modern: {arch}.{hv}.{platform}.installer.*  (≥3 parts)
            // Legacy:  {arch}.installer.img                (1 part, older EVE ≤12.x)
            QString prefix = name.chopped(suffixLen);
            QStringList parts = prefix.split(QLatin1Char('.'));
            if (parts.isEmpty())
                continue;

            AssetInfo asset;
            asset.arch       = parts[0];
            asset.hypervisor = parts.size() >= 2 ? parts[1] : QStringLiteral("kvm");
            asset.platform   = parts.size() >= 3 ? parts.mid(2).join(QLatin1Char('.')) : QStringLiteral("generic");
            asset.downloadUrl = ao["browser_download_url"].toString();
            asset.size        = ao["size"].toVariant().toLongLong();
            asset.isIso       = isIso;

            // Priority: .raw (1) > .raw.zst (2) > .iso (3)
            // For each arch/hv/platform combo keep only the highest-priority asset.
            int newPriority = isRaw ? 1 : isRawZst ? 2 : 3;

            bool replaced = false;
            for (int i = 0; i < assets.size(); ++i) {
                if (assets[i].arch == asset.arch
                    && assets[i].hypervisor == asset.hypervisor
                    && assets[i].platform == asset.platform) {
                    // Replace existing only if new asset has higher priority
                    int existingPriority = assets[i].isIso ? 3
                                        : assets[i].downloadUrl.endsWith(QLatin1String(".zst")) ? 2 : 1;
                    if (newPriority < existingPriority)
                        assets[i] = asset;
                    replaced = true;
                    break;
                }
            }
            if (replaced)
                goto nextAsset;

            assets.append(asset);
            nextAsset:;
        }

        if (assets.isEmpty())
            continue;   // No installer images for this release — skip

        ReleaseInfo rel;
        rel.version     = tagName;
        rel.publishedAt = publishedAt;
        rel.isLts       = isLts;
        rel.assets      = assets;
        _releases.append(rel);
    }

    qDebug() << "EveReleaseFetcher: parsed page" << _currentPage
             << "—" << entryCount << "entries," << _releases.size() << "with assets total";
    return entryCount;
}

// ── Property accessors ────────────────────────────────────────────────────────

QStringList EveReleaseFetcher::versions() const
{
    // Check whether any LTS releases exist at all
    bool anyLts = false;
    for (const ReleaseInfo &r : _releases) {
        if (r.isLts) { anyLts = true; break; }
    }

    // LTS filter active: show the single best LTS release per major version.
    // "Best" = latest LTS with arm64 assets; fall back to latest LTS with any arch.
    // Releases are already sorted newest-first, so the first qualifying entry wins.
    if (!_showNonLts && anyLts) {
        // Pass 1: latest LTS with arm64 per major
        QHash<QString, QString> arm64Best;   // major -> version
        QHash<QString, QString> anyBest;     // major -> version (any arch)
        for (const ReleaseInfo &r : _releases) {
            if (!r.isLts) continue;
            QString ver = r.version;
            if (ver.startsWith(QLatin1Char('v'), Qt::CaseInsensitive))
                ver = ver.mid(1);
            const QString major = ver.section(QLatin1Char('.'), 0, 0);
            bool hasArm64 = false;
            for (const AssetInfo &a : r.assets)
                if (a.arch == QLatin1String("arm64")) { hasArm64 = true; break; }
            if (!anyBest.contains(major))
                anyBest[major] = r.version;
            if (hasArm64 && !arm64Best.contains(major))
                arm64Best[major] = r.version;
        }
        // Pick arm64-capable version; fall back to any-arch version
        QStringList result;
        for (auto it = anyBest.keyBegin(); it != anyBest.keyEnd(); ++it) {
            const QString &major = *it;
            result.append(arm64Best.value(major, anyBest.value(major)));
        }
        // Sort by major version number descending (16.x before 14.x before 9.x)
        std::sort(result.begin(), result.end(), [](const QString &a, const QString &b) {
            auto majorOf = [](const QString &v) {
                QString s = v.startsWith(QLatin1Char('v'), Qt::CaseInsensitive) ? v.mid(1) : v;
                return s.section(QLatin1Char('.'), 0, 0).toInt();
            };
            return majorOf(a) > majorOf(b);
        });
        return result;
    }

    // Non-LTS mode (or no LTS releases found): return everything as-is.
    QStringList result;
    result.reserve(_releases.size());
    for (const ReleaseInfo &r : _releases)
        result.append(r.version);
    return result;
}

bool EveReleaseFetcher::isLtsVersion(const QString &version) const
{
    for (const ReleaseInfo &r : _releases) {
        if (r.version == version)
            return r.isLts;
    }
    return false;
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
