/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (C) 2025 Raspberry Pi Ltd
 */

#include <catch2/catch_test_macros.hpp>
#include <catch2/matchers/catch_matchers_string.hpp>

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QFile>
#include <QTemporaryDir>
#include <QThread>

#include "../asynccachewriter.h"
#include "../config.h"

// Helper: compute expected SHA256 hex of a byte sequence
static QByteArray sha256Hex(const QByteArray &data)
{
    return QCryptographicHash::hash(data, QCryptographicHash::Sha256).toHex();
}

// Helper: read entire file contents
static QByteArray readFile(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return f.readAll();
}

TEST_CASE("AsyncCacheWriter: basic open/write/finish", "[asynccachewriter]")
{
    QTemporaryDir tmp;
    REQUIRE(tmp.isValid());
    QString path = tmp.filePath("cache.bin");

    AsyncCacheWriter writer;
    REQUIRE(writer.open(path));
    REQUIRE(writer.isActive());

    QByteArray payload("Hello, world!");
    REQUIRE(writer.write(payload.constData(), static_cast<size_t>(payload.size())));

    writer.finish();

    REQUIRE_FALSE(writer.hasError());
    REQUIRE(QFile::exists(path));
    REQUIRE(readFile(path) == payload);
    REQUIRE(writer.hash() == sha256Hex(payload));
}

TEST_CASE("AsyncCacheWriter: multiple writes accumulate correctly", "[asynccachewriter]")
{
    QTemporaryDir tmp;
    REQUIRE(tmp.isValid());
    QString path = tmp.filePath("cache.bin");

    AsyncCacheWriter writer;
    REQUIRE(writer.open(path));

    QByteArray chunk1("chunk-one-");
    QByteArray chunk2("chunk-two-");
    QByteArray chunk3("chunk-three");
    REQUIRE(writer.write(chunk1.constData(), static_cast<size_t>(chunk1.size())));
    REQUIRE(writer.write(chunk2.constData(), static_cast<size_t>(chunk2.size())));
    REQUIRE(writer.write(chunk3.constData(), static_cast<size_t>(chunk3.size())));

    writer.finish();

    REQUIRE_FALSE(writer.hasError());
    QByteArray expected = chunk1 + chunk2 + chunk3;
    REQUIRE(readFile(path) == expected);
    REQUIRE(writer.hash() == sha256Hex(expected));
}

TEST_CASE("AsyncCacheWriter: open while already active returns false", "[asynccachewriter]")
{
    QTemporaryDir tmp;
    REQUIRE(tmp.isValid());
    QString path1 = tmp.filePath("cache1.bin");
    QString path2 = tmp.filePath("cache2.bin");

    AsyncCacheWriter writer;
    REQUIRE(writer.open(path1));
    REQUIRE_FALSE(writer.open(path2)); // Already active

    writer.cancel();
}

TEST_CASE("AsyncCacheWriter: write before open returns false", "[asynccachewriter]")
{
    AsyncCacheWriter writer;
    QByteArray data("test");
    // Not opened — _isActive is false, write should return false
    REQUIRE_FALSE(writer.write(data.constData(), static_cast<size_t>(data.size())));
}

TEST_CASE("AsyncCacheWriter: cancel removes cache file", "[asynccachewriter]")
{
    QTemporaryDir tmp;
    REQUIRE(tmp.isValid());
    QString path = tmp.filePath("cache.bin");

    AsyncCacheWriter writer;
    REQUIRE(writer.open(path));

    QByteArray data("some data that should be discarded");
    writer.write(data.constData(), static_cast<size_t>(data.size()));

    writer.cancel();

    // After cancel the file should be gone
    REQUIRE_FALSE(QFile::exists(path));
}

TEST_CASE("AsyncCacheWriter: isActive reflects writer state", "[asynccachewriter]")
{
    QTemporaryDir tmp;
    REQUIRE(tmp.isValid());
    QString path = tmp.filePath("cache.bin");

    AsyncCacheWriter writer;
    REQUIRE_FALSE(writer.isActive());

    REQUIRE(writer.open(path));
    REQUIRE(writer.isActive());

    writer.finish();
    REQUIRE_FALSE(writer.isActive());
}

TEST_CASE("AsyncCacheWriter: empty write produces correct hash", "[asynccachewriter]")
{
    QTemporaryDir tmp;
    REQUIRE(tmp.isValid());
    QString path = tmp.filePath("empty.bin");

    AsyncCacheWriter writer;
    REQUIRE(writer.open(path));
    writer.finish();

    REQUIRE_FALSE(writer.hasError());
    // SHA256 of empty string
    REQUIRE(writer.hash() == sha256Hex(QByteArray()));
}

TEST_CASE("AsyncCacheWriter: large write produces correct hash", "[asynccachewriter]")
{
    QTemporaryDir tmp;
    REQUIRE(tmp.isValid());
    QString path = tmp.filePath("large.bin");

    // 2 MB of data written in 64 KB chunks
    const int chunkSize = 64 * 1024;
    const int numChunks = 32;
    QByteArray chunk(chunkSize, 'A');
    QByteArray allData;
    allData.reserve(chunkSize * numChunks);

    AsyncCacheWriter writer;
    REQUIRE(writer.open(path));

    for (int i = 0; i < numChunks; ++i) {
        chunk.fill(static_cast<char>('A' + (i % 26)));
        allData.append(chunk);
        REQUIRE(writer.write(chunk.constData(), static_cast<size_t>(chunk.size())));
    }

    writer.finish();

    REQUIRE_FALSE(writer.hasError());
    REQUIRE(readFile(path) == allData);
    REQUIRE(writer.hash() == sha256Hex(allData));
}

TEST_CASE("AsyncCacheWriter: finish on inactive writer is safe", "[asynccachewriter]")
{
    AsyncCacheWriter writer;
    // finish() on a writer that was never opened should not crash
    REQUIRE_NOTHROW(writer.finish());
}

TEST_CASE("AsyncCacheWriter: cancel on inactive writer is safe", "[asynccachewriter]")
{
    AsyncCacheWriter writer;
    REQUIRE_NOTHROW(writer.cancel());
}
