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
- **Auto-install** — if `smartctl` or even Homebrew are missing, the app offers to install them with one click
- **Single admin prompt** — batches all `smartctl` commands into one authentication
- **Native macOS UI** — sidebar + detail, dark/light mode, native materials

## Requirements

- macOS 14.0+ (Apple Silicon or Intel)
- Internet connection (only if auto-install is needed)

## Usage

1. Open `DiskInfo.app` or run from source:
   ```bash
   swift run
   ```
2. If `smartctl` is not found, the app will offer to install it automatically (one click).
3. Authorize the admin prompt to read SMART data (one-time per session).

No manual setup required.

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
- **`smartctl`** (from [smartmontools](https://www.smartmontools.org)) — reads detailed SMART/health data via NVMe or ATA protocols

If `smartctl` is missing, the app auto-installs it via Homebrew (`brew install smartmontools`). If Homebrew itself is missing, it installs that too. All privileged operations run through a single `osascript` admin-authenticated call.

## License

MIT
