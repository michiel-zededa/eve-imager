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
#include <QObject>
#include <QStringList>
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
        qint64  size = 0;
        bool    isIso = false;  // true = .installer.iso, false = .installer.raw
    };

    struct ReleaseInfo {
        QString          version;       // e.g. "12.5.0"
        QDateTime        publishedAt;   // from GitHub published_at field
        bool             isLts = false; // true if tag/name contains "lts"
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
     * first.  When showNonLts is false, only LTS-tagged releases are returned
     * (unless no LTS releases exist, in which case all are returned).
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

signals:
    void releasesReady();
    void loadingChanged();
    void fetchFailedChanged();
    void statusMessageChanged();
    void showNonLtsChanged();
    void fetchFailed(const QString &message);

private slots:
    void onFetchFinished(const QByteArray &data, const QUrl &url, const QUrl &effectiveUrl);
    void onFetchError(const QString &errorMessage, const QUrl &url);

private:
    void parseReleases(const QByteArray &json);
    void setLoading(bool v);
    void setFetchFailed(bool v);
    void setStatusMessage(const QString &msg);

    const AssetInfo *findAsset(const QString &version,
                               const QString &arch,
                               const QString &hypervisor,
                               const QString &platform) const;

    QList<ReleaseInfo> _releases;
    bool    _loading     = false;
    bool    _fetchFailed = false;
    bool    _showNonLts  = false;
    QString _statusMessage;
};

#endif // EVERELEASEFETCHER_H
