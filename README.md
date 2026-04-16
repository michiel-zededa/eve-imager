# EVE-Imager

A graphical tool for writing [LF Edge EVE OS](https://github.com/lf-edge/eve) installer images to USB drives. Built on top of [Raspberry Pi Imager](https://github.com/raspberrypi/rpi-imager).

EVE-Imager downloads EVE OS releases directly from GitHub, lets you configure device settings (controller URL, network, certificates), writes the image to a USB drive, and verifies the result — all in one guided workflow.

---

## Features

- **Live release browser** — fetches available EVE OS versions directly from the [lf-edge/eve GitHub releases](https://github.com/lf-edge/eve/releases); no manual URL hunting required
- **Cascading selection** — choose Version → Architecture → Hypervisor → Platform; only combinations that actually have installer assets are shown
- **Raw and ISO support** — prefers `.installer.raw` images; falls back to `.installer.iso` when only an ISO is available for a combination
- **Device configuration** — optionally pre-configure the device before writing:
  - Controller URL and custom CA certificate
  - Network mode: DHCP or static IP (address, gateway, DNS)
  - HTTP/HTTPS proxy
  - Onboarding certificate and key
  - Device serial number (soft serial)
  - SSH public key for debug console access
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

Requirements: Xcode command-line tools, CMake ≥ 3.16, Qt 6.x

```bash
git clone https://github.com/michiel-zededa/eve-imager.git
cd eve-imager
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
# Sign locally (ad-hoc, no Apple Developer account needed):
find build/eve-imager.app \( -name "*.dylib" -o -name "*.so" \) | \
    awk '{print length, $0}' | sort -rn | cut -d' ' -f2- | \
    xargs -I{} codesign --force --sign - "{}"
find build/eve-imager.app -name "*.framework" -type d | \
    awk '{print length, $0}' | sort -rn | cut -d' ' -f2- | \
    xargs -I{} codesign --force --sign - "{}"
codesign --force --sign - build/eve-imager.app/Contents/MacOS/eve-imager
codesign --force --sign - build/eve-imager.app
open build/eve-imager.app
```

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

1. **Version** — Select an EVE OS version from the dropdown (loaded live from GitHub). Choose architecture, hypervisor, and platform. Or switch to the _Use local image file_ tab to pick a `.raw` file you already have.

2. **Storage** — Select the target USB drive. Double-check the device name and size before continuing.

3. **Configuration** _(optional)_ — Configure any combination of the settings below. Leave everything blank to write a vanilla image and configure the device through the controller later.

4. **Write** — Review the summary and click **Write**. EVE-Imager downloads the image (if not using a local file), streams it to the USB drive, and verifies the result.

5. **Done** — Eject the USB drive and boot your target device from it.

---

## Supported EVE OS images

EVE OS publishes installer images for:

| Architecture | Hypervisor | Platform examples |
|---|---|---|
| amd64 | kvm | generic |
| amd64 | k | generic (ISO only) |
| arm64 | kvm | generic, nvidia-jp5, nvidia-jp6 |

> **Note:** ISO images (`amd64.k.generic`) can be written to USB as bootable installers, but device configuration (controller URL, network settings) cannot be applied to ISO images — only to `.raw` images.

---

## Configuration details

When you fill in the Configuration step, EVE-Imager writes the following files to the `CONFIG` FAT partition on the USB drive before ejecting:

### Controller

| File | Description |
|---|---|
| `server` | Controller hostname, e.g. `zedcloud.example.zededa.net` |
| `root-certificate.pem` | CA certificate used to verify TLS connections to the controller. Required for self-hosted or private controller deployments. |

### Networking

| File | Description |
|---|---|
| `DevicePortConfig/override.json` | Network port configuration. Written when static IP or a proxy is configured; omitted for plain DHCP. |

### Device identity

| File | Description |
|---|---|
| `onboard.cert.pem` | Onboarding certificate — must be pre-registered in the controller. |
| `onboard.key.pem` | Matching onboarding private key. |
| `soft_serial` | Software-defined serial number sent to the controller at registration. Used to pre-provision or auto-approve a device. |

### SSH access

| File | Description |
|---|---|
| `authorized_keys` | SSH public key (OpenSSH format) for debug console access on the device. |

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
cmake -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build
```

### Running with debug logging

```bash
sudo ./build/eve-imager.app/Contents/MacOS/eve-imager --log-file /tmp/eve-imager.log
```

---

## Based on

EVE-Imager is a fork of [Raspberry Pi Imager](https://github.com/raspberrypi/rpi-imager) (Apache 2.0).  
The core write engine, FAT partition handling, and cross-platform build system are inherited from that project.

---

## License

Apache License 2.0 — see [LICENSE](./LICENSE) for details.

Copyright (C) 2020 Raspberry Pi Ltd (original)  
Copyright (C) 2025 ZEDEDA, Inc. (EVE-Imager additions)
