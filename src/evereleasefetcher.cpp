/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 ZEDEDA, Inc.
 */

#include "evereleasefetcher.h"
#include "curlfetcher.h"

#include <QDebug>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QPair>
#include <QRegularExpression>
#include <QUrl>
#include <algorithm>
#include <limits>

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

// ── Decompressed size of compressed images ───────────────────────────────────

// A zstd frame header is at most 18 bytes (4 magic + 1 descriptor + 1 window
// + 4 dictionary id + 8 content size); ask for a little more than that.
static const qint64 ZSTD_HEADER_PROBE_BYTES = 64;

qint64 EveReleaseFetcher::zstdFrameContentSize(const QByteArray &head)
{
    // Layout per RFC 8878, section 3.1.1.1 (all integers little-endian):
    //   Magic_Number (4) | Frame_Header_Descriptor (1) | [Window_Descriptor (1)]
    //   | [Dictionary_ID (0/1/2/4)] | [Frame_Content_Size (0/1/2/4/8)]
    const auto *b = reinterpret_cast<const unsigned char *>(head.constData());
    const qsizetype n = head.size();
    if (n < 6 || b[0] != 0x28 || b[1] != 0xB5 || b[2] != 0x2F || b[3] != 0xFD)
        return 0;

    const unsigned descriptor   = b[4];
    const unsigned fcsFlag      = descriptor >> 6;
    const bool     singleSegment = (descriptor >> 5) & 1;
    const unsigned dictFlag     = descriptor & 3;
    if (descriptor & 0x08)      // reserved bit must be zero
        return 0;

    static const int dictBytes[4] = {0, 1, 2, 4};
    static const int fcsBytesTab[4] = {0, 2, 4, 8};
    int fcsBytes = fcsBytesTab[fcsFlag];
    if (fcsFlag == 0 && singleSegment)
        fcsBytes = 1;
    if (fcsBytes == 0)          // frame does not state its content size
        return 0;

    qsizetype pos = 5;
    if (!singleSegment)
        pos += 1;               // Window_Descriptor
    pos += dictBytes[dictFlag];
    if (n < pos + fcsBytes)
        return 0;

    quint64 value = 0;
    for (int i = fcsBytes - 1; i >= 0; --i)
        value = (value << 8) | b[pos + i];
    if (fcsBytes == 2)
        value += 256;           // the 2-byte form is stored with an offset
    if (value > quint64(std::numeric_limits<qint64>::max()))
        return 0;
    return qint64(value);
}

void EveReleaseFetcher::probeImageSize(const QString &url)
{
    if (url.isEmpty() || !url.endsWith(QLatin1String(".zst"), Qt::CaseInsensitive))
        return;
    if (_imageSizes.contains(url))
        return;                 // already known
    const QUrl requestUrl(url);
    if (_pendingProbes.contains(requestUrl))
        return;                 // already on its way

    const bool wasIdle = _pendingProbes.isEmpty();
    _pendingProbes.insert(requestUrl, url);
    if (wasIdle)
        emit probingImageSizeChanged();

    auto *fetcher = new CurlFetcher(this);
    fetcher->setFirstBytesOnly(ZSTD_HEADER_PROBE_BYTES);
    connect(fetcher, &CurlFetcher::finished, this, &EveReleaseFetcher::onProbeFinished);
    connect(fetcher, &CurlFetcher::error,    this, &EveReleaseFetcher::onProbeError);
    fetcher->fetch(requestUrl);
}

qint64 EveReleaseFetcher::imageSize(const QString &url) const
{
    return _imageSizes.value(url, 0);
}

void EveReleaseFetcher::onProbeFinished(const QByteArray &data,
                                        const QUrl &url,
                                        const QUrl & /*effectiveUrl*/)
{
    const qint64 size = zstdFrameContentSize(data);
    if (size <= 0)
        qWarning() << "EveReleaseFetcher: no content size in the zstd header of" << url.toString();
    finishProbe(url, size);
}

void EveReleaseFetcher::onProbeError(const QString &errorMessage, const QUrl &url)
{
    qWarning() << "EveReleaseFetcher: could not read the image size of" << url.toString()
               << "-" << errorMessage;
    finishProbe(url, 0);
}

void EveReleaseFetcher::finishProbe(const QUrl &url, qint64 size)
{
    const QString assetUrl = _pendingProbes.take(url);
    if (!assetUrl.isEmpty() && size > 0) {
        _imageSizes.insert(assetUrl, size);
        emit imageSizeKnown(assetUrl, size);
    }
    if (_pendingProbes.isEmpty())
        emit probingImageSizeChanged();
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

        // Detect LTS: EVE tags its LTS releases "X.Y.Z-lts". That suffix is the
        // only reliable signal — the minor version's parity is not (14.5.5-lts
        // is an LTS release with an odd minor), so no guessing from the number.
        static const QRegularExpression ltsTagRe(
            QStringLiteral("^v?(\\d+)\\.(\\d+)\\.(\\d+)-lts$"),
            QRegularExpression::CaseInsensitiveOption);
        const QRegularExpressionMatch ltsMatch = ltsTagRe.match(tagName);
        const bool isLts = ltsMatch.hasMatch();

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
            // .raw.zst is zstd-compressed and .installer.img is gzip-compressed;
            // for both, the asset size is the compressed size, not the image size.
            asset.isCompressed = isRawZst
                              || name.endsWith(QLatin1String(".installer.img"));

            // Sanity-check: a real EVE installer is always >250 MB even when compressed.
            // Tiny assets in old releases are bootstrap/netboot files, not full disk images.
            static constexpr qint64 MIN_INSTALLER_BYTES = 250LL * 1024 * 1024; // 250 MB
            if (asset.size > 0 && asset.size < MIN_INSTALLER_BYTES)
                continue;

            // Priority: .raw.zst (1) > .raw / legacy .img (2) > .iso (3)
            // For each arch/hv/platform combo keep only the highest-priority asset.
            // The zstd-compressed raw image is preferred over the plain one: it is
            // the same disk image, a much smaller download, and it is decompressed
            // on the fly while writing.
            int newPriority = isRawZst ? 1 : isRaw ? 2 : 3;

            bool replaced = false;
            for (int i = 0; i < assets.size(); ++i) {
                if (assets[i].arch == asset.arch
                    && assets[i].hypervisor == asset.hypervisor
                    && assets[i].platform == asset.platform) {
                    // Replace existing only if new asset has higher priority
                    int existingPriority = assets[i].isIso ? 3
                                        : assets[i].downloadUrl.endsWith(QLatin1String(".zst")) ? 1 : 2;
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
        if (isLts) {
            rel.verMajor = ltsMatch.captured(1).toInt();
            rel.verMinor = ltsMatch.captured(2).toInt();
            rel.verPatch = ltsMatch.captured(3).toInt();
        }
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

    // LTS filter active: show the newest patch release of every LTS line (X.Y).
    //
    // "Newest" is decided by the patch number, not the publication date, so a
    // back-ported patch on an older line cannot shadow anything.
    //
    // The newest patch is tracked per architecture: if the newest patch of a
    // line was published without (say) arm64 assets, the newest older patch
    // that does have them is listed as well, so no architecture loses access
    // to a line. In the normal case every architecture agrees and the line
    // contributes exactly one entry.
    if (!_showNonLts && anyLts) {
        struct Pick { int patch = -1; QString version; };
        // (major, minor) -> arch -> newest patch offering that arch
        QMap<QPair<int, int>, QHash<QString, Pick>> lines;
        for (const ReleaseInfo &r : _releases) {
            if (!r.isLts) continue;
            QHash<QString, Pick> &byArch = lines[qMakePair(r.verMajor, r.verMinor)];
            for (const AssetInfo &a : r.assets) {
                Pick &p = byArch[a.arch];
                if (r.verPatch > p.patch) {
                    p.patch = r.verPatch;
                    p.version = r.version;
                }
            }
        }

        // Newest line first; within a line, newest patch first.
        QStringList result;
        for (auto line = lines.constEnd(); line != lines.constBegin(); ) {
            --line;
            QMap<int, QString> byPatch;   // patch -> version (de-duplicates arches)
            for (const Pick &p : line.value())
                byPatch.insert(p.patch, p.version);
            for (auto v = byPatch.constEnd(); v != byPatch.constBegin(); ) {
                --v;
                result.append(v.value());
            }
        }
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

bool EveReleaseFetcher::isCompressedAsset(const QString &version,
                                          const QString &arch,
                                          const QString &hypervisor,
                                          const QString &platform) const
{
    const AssetInfo *a = findAsset(version, arch, hypervisor, platform);
    return a ? a->isCompressed : false;
}

QString EveReleaseFetcher::assetFileName(const QString &version,
                                         const QString &arch,
                                         const QString &hypervisor,
                                         const QString &platform) const
{
    const AssetInfo *a = findAsset(version, arch, hypervisor, platform);
    return a ? QUrl(a->downloadUrl).fileName() : QString();
}
