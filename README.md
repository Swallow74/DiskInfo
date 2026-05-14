# DiskInfo

![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift)
![macOS](https://img.shields.io/badge/macOS-14.0+-blue?logo=apple)
![License](https://img.shields.io/badge/License-MIT-green)

A native macOS app that displays detailed SMART information for all connected disks — internal NVMe, external USB, and SATA drives.

Built with **SwiftUI** and **Swift 6**, no Xcode required.

## Features

- **Real-time disk scan** — detects all physical disks via `diskutil`
- **SMART health data** — temperature, wear, spare, usage, reliability
- **All temperature sensors** — shows every sensor the drive reports
- **Progress bars** — visual indicators for health % and spare
- **SATA support** — reallocated sectors, pending sectors, CRC errors
- **Technical details** — full `smartctl` raw output parsed (NVMe version, PCI vendor, power states, etc.)
- **Single admin prompt** — batches all smartctl commands into one authentication
- **Native macOS UI** — sidebar + detail, dark/light mode, native materials

## Requirements

- macOS 14.0+ (Apple Silicon or Intel)
- [smartmontools](https://www.smartmontools.org) (`brew install smartmontools`)

## Usage

1. Install smartmontools:
   ```bash
   brew install smartmontools
   ```

2. Open `DiskInfo.app` or run from source:
   ```bash
   swift run
   ```

3. Authorize the admin prompt when asked (one-time per session).

## Build from Source

```bash
git clone https://github.com/Swallow74/DiskInfo.git
cd DiskInfo
swift build -c release
cp .build/arm64-apple-macosx/release/DiskInfo DiskInfo.app/Contents/MacOS/DiskInfo
```

## How It Works

The app uses two command-line tools behind the scenes:

- **`diskutil`** (built into macOS) — lists disks and retrieves basic info (model, size, interface)
- **`smartctl`** (from smartmontools) — reads detailed SMART/health data via NVMe or ATA protocols

All privileged commands run through a single `osascript` admin-authenticated call. The bundled `smartctl` was removed because macOS SIP kills unsigned binaries when run as root.

## License

MIT
