# Architecture

EVE Imager is a Qt6-based GUI application for writing LF Edge EVE OS images to USB drives.
It is forked from Raspberry Pi Imager and extends it with EVE-specific release browsing,
device pre-configuration, and a multi-step wizard UI.

---

## High-Level Structure

```
┌─────────────────────────────────────────────────────────┐
│                       QML UI (wizard/)                  │
│  Step1 → Step2 → Step3(config) → Step4(write) → Step5  │
└────────────────────────┬────────────────────────────────┘
                         │ Q_INVOKABLE / signals
┌────────────────────────▼────────────────────────────────┐
│                    ImageWriter (C++)                     │
│  Central controller; owns models, threads, cache mgr    │
└──┬──────────────┬──────────────┬────────────────────────┘
   │              │              │
   ▼              ▼              ▼
DriveListModel  OSListModel   DownloadThread / LocalFileExtractThread
(drive poll)  (JSON fetch)   (download → decompress → write → verify)
                                  │
                     ┌────────────┴──────────────┐
                     ▼                           ▼
              FileOperations            AsyncCacheWriter
          (platform I/O: Linux          (background cache
           io_uring / Win IOCP /         file writer)
           macOS GCD)
```

---

## Core Components

### `ImageWriter` (`imagewriter.h/.cpp`)
The central Qt controller object, exposed to QML.  It owns:
- `DriveListModel` — polls connected block devices
- `OSListModel` / EVE release fetcher — fetches and filters the image list
- `CacheManager` — tracks local cached images and their hashes
- The active `DownloadThread` or `LocalFileExtractThread`

All QML interactions go through `ImageWriter` via `Q_INVOKABLE` methods and Qt signals.

### `DownloadThread` (`downloadthread.h/.cpp`)
A `QThread` that performs the full write pipeline:
1. HTTP download via libcurl (with progress signals)
2. Decompression (gzip / xz / zstd / bzip2 via libarchive)
3. Write to block device via `FileOperations`
4. Optional post-write SHA256 verification
5. Optional bmap-accelerated sparse writing

Communicates status back to `ImageWriter` via Qt signals.  Has an adaptive
bottleneck-detection system that identifies whether the limiting factor is
network, decompression, or storage speed.

### `FileOperations` (`file_operations.h`)
Abstract interface for block-device I/O, with three platform implementations:

| Platform | Implementation | Async backend |
|----------|---------------|---------------|
| Linux    | `LinuxFileOperations`   | io_uring (fallback: sync) |
| Windows  | `WindowsFileOperations` | IOCP |
| macOS    | `MacOSFileOperations`   | GCD `dispatch_io` |

Key capabilities: direct I/O (page-cache bypass), async queue depth tuning,
automatic fallback to synchronous I/O on stall, per-write latency statistics.

### `AsyncCacheWriter` (`asynccachewriter.h/.cpp`)
A `QThread` that writes downloaded data to the local disk cache in the background,
so cache I/O never blocks the main write path.  Uses an adaptive in-memory queue
sized to available system RAM.  Computes SHA256 of all written data for cache
validation.

### EVE-specific Components
- **`EveReleaseFetcher`** — queries the GitHub releases API, parses version/
  architecture/hypervisor/platform metadata, and populates the OS list.
- **`EveConfigurator`** — writes EVE device pre-configuration into the image
  (controller URL, network settings, certificates, SSH keys) using the
  `DeviceWrapperFatPartition` API.

### `DeviceWrapperFatPartition` (`devicewrapperfatpartition.h/.cpp`)
Implements FAT12/16/32 read/write operations on top of a raw partition image,
used to inject configuration files into EVE boot partitions.  Supports full
CRUD (create, read, update, delete) including LFN directory entries, cluster
chain management, and FSinfo updates.

### Wizard UI (`src/wizard/`)
Five-step QML wizard built on Qt Quick Controls 2:

| Step | File | Purpose |
|------|------|---------|
| 1 | `Step1Version.qml` | Select EVE version / arch / platform |
| 2 | `Step2Storage.qml` | Select write destination |
| 3 | `Step3Config.qml`  | Device pre-configuration (network, certs, SSH) |
| 4 | `Step4Write.qml`   | Progress display, write + verify |
| 5 | `Step5Done.qml`    | Success / eject |

Shared dialogs (`dialogs/`) handle repository selection, SSH key import,
advanced image options, and network configuration.

---

## Threading Model

```
Main thread (Qt event loop)
  │
  ├─ ImageWriter (lives here, drives QML binding)
  ├─ DriveListModel polling (QTimer)
  │
  └─ Worker threads (started on demand, signals back to main)
       ├─ DownloadThread          — download + write pipeline
       ├─ AsyncCacheWriter        — background cache writes
       ├─ DownloadExtractThread   — local file extract path
       ├─ FastbootFlashThread     — fastboot flashing path
       └─ IconMultiFetcher thread — curl_multi icon downloads
```

All cross-thread communication uses Qt signals/slots with `Qt::QueuedConnection`.

---

## Logging

Structured logging uses Qt's `QLoggingCategory` (defined in `src/logging.h`).
Categories map to subsystems:

| Category       | Domain          |
|----------------|-----------------|
| `rpi.download` | HTTP download   |
| `rpi.write`    | Device write    |
| `rpi.verify`   | Verification    |
| `rpi.cache`    | AsyncCacheWriter|
| `rpi.fat`      | FAT operations  |
| `rpi.drivelist`| Drive poll      |
| `rpi.icons`    | Icon fetcher    |
| `rpi.platform` | Platform quirks |
| `rpi.rpiboot`  | rpiboot protocol|
| `rpi.fastboot` | fastboot protocol|
| `rpi.eve`      | EVE release/config|

Runtime filtering via environment variable:
```
QT_LOGGING_RULES="rpi.icons=false;rpi.fat.debug=false" ./rpi-imager
```

---

## Build System

CMake 3.22+ with Qt6.  Platform-specific sources are conditionally included
based on `WIN32` / `APPLE` / Linux guards.  Tests use Catch2 v3 (fetched via
`FetchContent`) and are registered with CTest via `catch_discover_tests()`.

Key build targets:
- `rpi-imager` — the main application
- `customization_generator_test` — customization logic tests
- `asynccachewriter_test` — cache writer unit tests
- `fat_partition_test` — FAT filesystem tests (requires `FAT_TEST_MOUNT_PATH`)
- `rpiboot_protocol_test` — rpiboot mock-transport tests
- `fastboot_protocol_test` — fastboot protocol tests
- `platformquirks_test` — platform quirk tests

Deployment packaging:
- Linux: AppImage via `scripts/build-appimage.sh`
- macOS: signed `.app` / `.dmg`
- Windows: Inno Setup installer

---

## Key Data Flows

### Normal write flow
```
User clicks Write
  → ImageWriter::startWrite()
  → DownloadThread::start()
       libcurl callback → _file->AsyncWriteSequential()
                       → AsyncCacheWriter::write()  (parallel)
  → DownloadThread emits writeProgress / success / error
  → ImageWriter receives signal → notifies QML
```

### Cache hit flow
```
User selects image that is cached
  → ImageWriter::isCached() == true
  → LocalFileExtractThread reads from cache file
  → Same write/verify pipeline as above
```
