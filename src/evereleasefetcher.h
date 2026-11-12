/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 ZEDEDA, Inc.
 *
 * EveReleaseFetcher — fetches EVE OS releases from the GitHub Releases API
 * and exposes version/arch/hypervisor/platform combinations to QML.
 *
 * Usage from QML:
 *   EveReleaseFetcher {
 *       id: fetcher
 *       Component.onCompleted: fetchReleases()
 *   }
 *   // bind version combo to fetcher.versions
 *   // query available options with archesForVersion(), hypervisorsFor(), platformsFor()
 *   // get the download URL with downloadUrl()
 */

#ifndef EVERELEASEFETCHER_H
#define EVERELEASEFETCHER_H

#include <QDateTime>
#include <QHash>
#include <QObject>
#include <QStringList>
#include <QUrl>
#include <QVariantMap>
#ifndef CLI_ONLY_BUILD
#include <QQmlEngine>
#endif

class EveReleaseFetcher : public QObject
{
    Q_OBJECT
#ifndef CLI_ONLY_BUILD
    QML_ELEMENT
#endif

    // ── Internal data structures ──────────────────────────────────────────
    struct AssetInfo {
        QString arch;
        QString hypervisor;
        QString platform;
        QString downloadUrl;
        qint64  size = 0;       // size of the asset as downloaded (compressed size if isCompressed)
        bool    isIso = false;  // true = .installer.iso, false = .installer.raw
        // true = the download is a compressed stream (.installer.raw.zst, or the
        // legacy gzip'd .installer.img), so `size` is NOT the size of the disk
        // image that ends up on the device.
        bool    isCompressed = false;
    };

    struct ReleaseInfo {
        QString          version;       // tag name, e.g. "17.0.1-lts"
        QDateTime        publishedAt;   // from GitHub published_at field
        bool             isLts = false; // true if the tag has the form X.Y.Z-lts
        // Parsed from an LTS tag (X.Y.Z-lts); -1 for other releases. X.Y is the
        // "LTS line"; the highest Z within a line is its newest patch release.
        int              verMajor = -1;
        int              verMinor = -1;
        int              verPatch = -1;
        QList<AssetInfo> assets;
    };

public:
    explicit EveReleaseFetcher(QObject *parent = nullptr);

    // ── Properties ────────────────────────────────────────────────────────

    /** True while a network fetch is in progress. */
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    bool loading() const { return _loading; }

    /** True if the last fetch attempt failed. */
    Q_PROPERTY(bool fetchFailed READ fetchFailed NOTIFY fetchFailedChanged)
    bool fetchFailed() const { return _fetchFailed; }

    /** Human-readable status ("Loading releases…", "Ready", or "Error: …"). */
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY statusMessageChanged)
    QString statusMessage() const { return _statusMessage; }

    /**
     * Version strings that have at least one installer asset, sorted newest
     * first.  When showNonLts is false, only the newest patch release of each
     * LTS line (X.Y) is returned (unless no LTS releases exist, in which case
     * all are returned).  If that newest patch lacks an architecture that an
     * older patch of the same line still offers, that older patch is listed too.
     */
    Q_PROPERTY(QStringList versions READ versions NOTIFY releasesReady)
    QStringList versions() const;

    /**
     * When false (default) only LTS releases are shown in the version list.
     * Set to true to include all releases.
     */
    Q_PROPERTY(bool showNonLts READ showNonLts WRITE setShowNonLts NOTIFY showNonLtsChanged)
    bool showNonLts() const { return _showNonLts; }
    void setShowNonLts(bool v);

    /**
     * True while the size of a compressed image is being looked up (see
     * probeImageSize()). The lookup is one small request and normally takes
     * well under a second.
     */
    Q_PROPERTY(bool probingImageSize READ probingImageSize NOTIFY probingImageSizeChanged)
    bool probingImageSize() const { return !_pendingProbes.isEmpty(); }

    // ── Invokable queries ─────────────────────────────────────────────────

    /** Trigger an async fetch from the GitHub Releases API. */
    Q_INVOKABLE void fetchReleases();

    /** Returns true if the given version string is an LTS release. */
    Q_INVOKABLE bool isLtsVersion(const QString &version) const;

    /** Unique architectures available for the given version. */
    Q_INVOKABLE QStringList archesForVersion(const QString &version) const;

    /** Unique hypervisors available for version + arch. */
    Q_INVOKABLE QStringList hypervisorsFor(const QString &version,
                                           const QString &arch) const;

    /** Unique platforms available for version + arch + hypervisor. */
    Q_INVOKABLE QStringList platformsFor(const QString &version,
                                         const QString &arch,
                                         const QString &hypervisor) const;

    /** Download URL for the specified combination, or empty string if not found. */
    Q_INVOKABLE QString downloadUrl(const QString &version,
                                    const QString &arch,
                                    const QString &hypervisor,
                                    const QString &platform) const;

    /** File size in bytes for the specified combination, or 0 if not found. */
    Q_INVOKABLE qint64 downloadSize(const QString &version,
                                    const QString &arch,
                                    const QString &hypervisor,
                                    const QString &platform) const;

    /** Returns true if the asset for this combination is an ISO (not a raw image). */
    Q_INVOKABLE bool isIsoAsset(const QString &version,
                                const QString &arch,
                                const QString &hypervisor,
                                const QString &platform) const;

    /**
     * Returns true if the asset for this combination is downloaded compressed
     * (.installer.raw.zst or legacy .installer.img). For such assets
     * downloadSize() is the compressed size, and the size of the extracted
     * disk image is not known up front.
     */
    Q_INVOKABLE bool isCompressedAsset(const QString &version,
                                       const QString &arch,
                                       const QString &hypervisor,
                                       const QString &platform) const;

    /** File name of the asset for this combination (e.g. "amd64.k.generic.installer.raw.zst"). */
    Q_INVOKABLE QString assetFileName(const QString &version,
                                      const QString &arch,
                                      const QString &hypervisor,
                                      const QString &platform) const;

    /**
     * Look up how large a zstd-compressed image (.zst) is once decompressed,
     * i.e. how much space it needs on the drive. The release metadata only
     * gives the compressed download size; the real size is stored in the
     * first bytes of the file, so only those are fetched.
     *
     * Asynchronous: imageSizeKnown() is emitted when the size has been read.
     * Nothing is emitted if it cannot be determined (the size then stays
     * unknown, which the writer copes with). Does nothing for other URLs or
     * for a URL that was already looked up.
     */
    Q_INVOKABLE void probeImageSize(const QString &url);

    /** Decompressed size in bytes found by probeImageSize() for this URL, or 0 if not known. */
    Q_INVOKABLE qint64 imageSize(const QString &url) const;

    /**
     * Decompressed size announced in the header of a zstd frame, given the
     * first bytes of the file; 0 if the data is not a zstd frame or the frame
     * does not state its content size.
     */
    static qint64 zstdFrameContentSize(const QByteArray &head);

signals:
    void releasesReady();
    void probingImageSizeChanged();
    void imageSizeKnown(const QString &url, qint64 size);
    void loadingChanged();
    void fetchFailedChanged();
    void statusMessageChanged();
    void showNonLtsChanged();
    void fetchFailed(const QString &message);

private slots:
    void onFetchFinished(const QByteArray &data, const QUrl &url, const QUrl &effectiveUrl);
    void onFetchError(const QString &errorMessage, const QUrl &url);
    void onProbeFinished(const QByteArray &data, const QUrl &url, const QUrl &effectiveUrl);
    void onProbeError(const QString &errorMessage, const QUrl &url);

private:
    void finishProbe(const QUrl &url, qint64 size);

    void fetchPage(int page);
    int  parseReleases(const QByteArray &json);  // returns raw JSON entry count
    void setLoading(bool v);
    void setFetchFailed(bool v);
    void setStatusMessage(const QString &msg);

    const AssetInfo *findAsset(const QString &version,
                               const QString &arch,
                               const QString &hypervisor,
                               const QString &platform) const;

    QList<ReleaseInfo> _releases;
    QHash<QString, qint64> _imageSizes;    // asset URL -> decompressed size, once probed
    QHash<QUrl, QString>   _pendingProbes; // request URL -> asset URL as given by the caller
    bool    _loading     = false;
    bool    _fetchFailed = false;
    bool    _showNonLts  = false;
    QString _statusMessage;
    int     _currentPage = 0;
    static constexpr int MAX_PAGES = 3;  // 3 × 100 = up to 300 releases
};

#endif // EVERELEASEFETCHER_H
