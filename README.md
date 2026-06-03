# EVE Imager

A graphical tool for writing [LF Edge EVE OS](https://github.com/lf-edge/eve) installer images to USB drives. Built on top of [Raspberry Pi Imager](https://github.com/raspberrypi/rpi-imager).

EVE Imager downloads EVE OS releases directly from GitHub, lets you configure device settings (controller URL, network, WiFi), writes the image to a USB drive, and verifies the result — all in one guided workflow.

---

## Features

- **Live release browser** — paginates all EVE OS releases from [lf-edge/eve GitHub releases](https://github.com/lf-edge/eve/releases), showing one entry per major version sorted highest first (16.x, 14.x, 13.x, …)
- **LTS filter** — shows only the latest LTS release per major version; prefers the release with arm64 support when available; use the _Use local image file_ tab for non-LTS builds
- **Cascading selection** — choose Version → Architecture → Hypervisor → Platform; only combinations that actually have installer assets are shown
- **Multi-format support** — handles `.installer.raw`, `.installer.raw.zst` (zstd-compressed, decompressed on the fly), and `.installer.iso`; prefers uncompressed raw over compressed over ISO; ISO images skip the config customization step. Note: older `.installer.img` assets (netboot/PXE format) are not USB-writable and are excluded
- **Device configuration** — optionally pre-configure the device before writing (RAW images only):
  - Controller URL
  - Network mode: DHCP or static IP (address, gateway, DNS)
  - HTTP/HTTPS proxy
  - WiFi (SSID and WPA2 password)
  - Target install disk and separate `/persist` disk
  - Auto-reboot after installation
- **Local image support** — bypass the GitHub release browser and write a locally downloaded `.raw` file instead
- **Write + verify** — streams the download directly to the USB device and verifies the written data afterwards
- **5-step wizard** — Version → Storage → Configuration → Write → Done

---

## Screenshots

> _Screenshots coming soon_

---

## Installation

### macOS (build from source)

Requirements: Xcode command-line tools, CMake ≥ 3.16, Qt 6.x (via Homebrew: `brew install qt`)

```bash
git clone https://github.com/michiel-zededa/eve-imager.git
cd eve-imager

# One-time: create a local code-signing certificate so the app runs permanently
./setup-codesign.sh

# Build and launch
./run-dev.sh --rebuild
```

`run-dev.sh` auto-detects your Qt installation and architecture, builds the app, signs it with the local certificate, and opens it. On subsequent runs you only need `./run-dev.sh` (no rebuild needed unless sources changed).

> **Note:** The build system (`cmake`) auto-signs the app after every rebuild. The `setup-codesign.sh` step only needs to be run once per machine.

#### Distributing to others

The local self-signed certificate is machine-specific and cannot be bundled with the app. For sharing with colleagues:

- **Quick option:** Recipients right-click the `.app` → **Open** the first time to bypass Gatekeeper. macOS remembers the exception.
- **Proper distribution:** Sign with an [Apple Developer ID](https://developer.apple.com/programs/) certificate and notarize — the app will then run on any Mac without any extra steps.

### Linux (build from source)

```bash
sudo apt install cmake qt6-base-dev qt6-declarative-dev \
    libcurl4-openssl-dev libssl-dev libudev-dev
git clone https://github.com/michiel-zededa/eve-imager.git
cd eve-imager
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
sudo ./build/eve-imager   # root required for raw device access
```

### Windows

Build with CMake + Qt 6 via the Qt Online Installer. Run as Administrator (raw device write access requires elevation).

---

## Usage

1. **Version** — Select an EVE OS version from the dropdown (loaded live from GitHub, newest first). Only LTS releases are shown (even minor version number — e.g. 12.0.x, 12.2.x). Choose architecture, hypervisor, and platform. Or switch to the _Use local image file_ tab to pick a `.raw` or `.iso` file you already have (useful for non-LTS builds).

2. **Storage** — Select the target USB drive. Double-check the device name and size before continuing.

3. **Configuration** _(optional, RAW images only)_ — Configure any combination of the settings below. Leave everything blank to write a plain image and configure the device through the controller later. This step is skipped automatically for ISO images.

4. **Write** — Review the summary and click **Write**. EVE-Imager downloads the image (if not using a local file), streams it to the USB drive, and verifies the result. A yellow notice is shown when writing an ISO to remind you that pre-configuration is not available.

5. **Done** — Eject the USB drive and boot your target device from it.

---

## Supported EVE OS images

EVE OS publishes installer images for:

| Architecture | Hypervisor | Platform examples |
|---|---|---|
| amd64 | kvm | generic, evaluation |
| amd64 | k | generic |
| arm64 | kvm | generic, nvidia-jp5, nvidia-jp6, nvidia-jp7 |
| arm64 | k | generic, nvidia-jp5, nvidia-jp6, nvidia-jp7 |

> **Note:** ISO images can be written to USB as bootable installers, but device configuration (controller URL, network settings) cannot be applied — only `.raw` and `.raw.zst` images have a CONFIG partition.

> **Note:** If a release is missing from the version list, it may be incorrectly marked as `prerelease=true` on GitHub. Ask the EVE team to correct the release — no code change is needed in EVE Imager.

---

## Configuration details

When you fill in the Configuration step, EVE-Imager writes the following files to the `CONFIG` FAT partition on the USB drive before ejecting:

### Controller

| File | Description |
|---|---|
| `server` | Controller hostname, e.g. `zedcloud.example.zededa.net` |

### Networking / WiFi

| File | Description |
|---|---|
| `DevicePortConfig/override.json` | Network port configuration. Written when static IP, a proxy, or a WiFi network is configured; omitted for plain wired DHCP. Includes a `wlan0` port with WPA2 credentials when an SSID is provided. |

The WiFi configuration uses EVE OS's native format: `WirelessTypeWifi = 2`, `WifiKeySchemeWpaPsk = 1`, `DhcpTypeClient = 4`, as defined in EVE's device model.

### Installation (written to `grub.cfg`)

| Kernel parameter | Description |
|---|---|
| `eve_install_disk=<disk>` | Force EVE to install onto a specific disk, e.g. `nvme0n1`. Useful on servers with multiple drives. |
| `eve_persist_disk=<disk>` | Put the `/persist` partition on a separate disk, e.g. `sda`. |
| `eve_reboot_after_install` | Automatically reboot when installation completes. |

---

## Development

### Project structure

```
src/
├── evereleasefetcher.{h,cpp}     # GitHub Releases API client
├── eveconfigurator.{h,cpp}       # Writes EVE config to CONFIG partition
├── devicewrapperfatpartition.*   # FAT12/16/32 partition read/write
├── imagewriter.{h,cpp}           # Core download + write engine
├── wizard/
│   ├── WizardContainer.qml       # 5-step wizard shell + sidebar
│   ├── EveVersionStep.qml        # Step 0: version / image selection
│   ├── StorageSelectionStep.qml  # Step 1: USB drive picker
│   ├── EveCustomizationStep.qml  # Step 2: controller + network config
│   ├── WritingStep.qml           # Step 3: progress + write
│   └── DoneStep.qml              # Step 4: completion
└── Style.qml                     # ZEDEDA brand colours + layout constants
```

### Building for development

```bash
# First time on a new machine:
./setup-codesign.sh          # creates a local code-signing certificate

./run-dev.sh --rebuild       # configure + build + sign + launch
./run-dev.sh                 # sign + launch (no rebuild)
```

`run-dev.sh` auto-detects your Qt installation (`brew --prefix qt`) and CPU architecture.

### Running with debug logging

```bash
./build/eve-imager.app/Contents/MacOS/eve-imager --log-file /tmp/eve-imager.log
```

---

## Based on

EVE Imager is a fork of [Raspberry Pi Imager](https://github.com/raspberrypi/rpi-imager) (Apache 2.0).  
The core write engine, FAT partition handling, and cross-platform build system are inherited from that project.

---

## License

Apache License 2.0 — see [LICENSE](./LICENSE) for details.

Copyright (C) 2020 Raspberry Pi Ltd (original)  
Copyright (C) 2025 ZEDEDA, Inc. (EVE-Imager additions)
