# Zalos 🚀

<div align="center">

**A high-performance, ultra-lightweight native Zalo desktop client for Linux**

[![CI/CD Pipeline](https://github.com/cpfriend1721994/zalos/actions/workflows/ci.yml/badge.svg)](https://github.com/cpfriend1721994/zalos/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Binary Size](https://img.shields.io/badge/Size-~6%20MB%20deb%2Frpm%20%7C%20~22%20MB%20AppImage-success.svg)](#-overview)
[![RAM Usage](https://img.shields.io/badge/RAM-~40--65%20MB-brightgreen.svg)](#-overview)
[![Platform](https://img.shields.io/badge/Platform-Wayland%20%7C%20X11-purple.svg)](#-features)
[![Packaging](https://img.shields.io/badge/Packaging-deb%20%7C%20RPM%20%7C%20AppImage%20%7C%20Nix-orange.svg)](#-installation)

[English](README.md) | [Tiếng Việt](README.vi.md) | [Website](https://cpfriend1721994.github.io/zalos/)

</div>

---

## 📖 Overview

**Zalos** is an open-source, **high-performance and ultra-lightweight** native desktop client for Zalo on Linux.
Written completely in native C++17 and Qt 6 QML, it replaces the resource-heavy Electron/Chromium runtime with a lean,
purpose-built architecture:

- **Ultra-lightweight:** Compact native `.deb`/`.rpm` (~6 MB) or self-contained AppImage (~22 MB with Qt 6.4 fallback) and minimal memory footprint (~40–65 MB RAM, saving over 90% compared to 450–1,800+ MB on Electron wrappers).
- **High performance:** Instant startup (<0.5s), hardware-accelerated 60 FPS graphics, multi-threaded C++ cryptographic decoding, and smooth responsiveness even on low-spec hardware.
- **Linux native:** Wayland & X11 support with system theme synchronization (light/dark), native desktop notifications, and seamless Vietnamese input.

### ⚡ Performance & Resource Benchmark

| Metric | Zalos (C++17 / Qt 6 QML) | Zalo PC / Electron Wrapper |
|---|---|---|
| **Runtime Memory (RAM)** | **~40 – 65 MB** (self-managed, >90% lighter) | 450 – 1,800+ MB (multiple Chromium processes) |
| **Package / Binary Size** | **~6 MB (`.deb`/`.rpm`) · ~22 MB (AppImage)** | > 150 – 250 MB (bundled browser runtime) |
| **Cold Startup Time** | **< 0.5s** (instantaneous launch) | 3 – 8s (V8 engine & browser init) |
| **UI Rendering** | **Hardware-accelerated Qt Quick (60 FPS)** | Web DOM / Chromium compositor |
| **Architecture** | **Pure Native C++17 & QML** | Electron / Node.js + Web wrapper |

---

## ✨ Features

- **High performance & ultra-lightweight** — sub-second startup (<0.5s), smooth 60 FPS Qt Quick rendering, ~6 MB native `.deb`/`.rpm` (~22 MB self-contained AppImage), and minimal RAM usage (~40–65 MB).
- **Wayland & X11** — runs on both, with native window controls on GNOME and KDE, plus a GPU hardware-acceleration toggle with instant restart in Settings.
- **Automatic light/dark theme** — follows your system colour scheme in real time.
- **Messaging** — one-to-one and group chats, animated Stickers, emoji, 54 Zalo reactions, replies,
  forwards, pinned messages, labels, conversation type filters (All / Groups / Direct), and full-history search.
- **Smart mobile history sync** — detects empty group histories on sign-in and offers encrypted phone sync.
- **Voice & video calls** — 1-1 voice/video calls with OpenH264 video encoding; group calls are in beta.
- **My Documents** — the personal storage thread with instant filters for photos, videos, files and links.
- **Desktop utilities** — screenshot capture (`Ctrl+Alt+S`), configurable Kiki assistant and zBusiness tools (profile, product catalog, auto reply).
- **Contacts & groups** — 1-click voice call, video call, and chat on every contact row, pending group invite box, friend recommendations, mutual groups in profiles, and Community upgrade for group owners.
- **Safety & devices** — Zalo safe link scanning (`scanURL`) before opening external links, message/profile abuse reporting, and E2EE linked devices viewer in Settings.
- **System tray** — unread-count badge and quick actions.
- **Offline history** — your conversations stay available without a connection.
- **In-app update support** — GitHub Releases check with SHA-256 verification (atomic self-update + `gh-releases-zsync` for AppImage; `pkexec`/system installer for `.deb`/`.rpm`).
- **Bilingual interface** — instant switching between Vietnamese and English.

> **Disclaimer:** Zalos is an independent open-source project and is **not** affiliated with, endorsed, or
> sponsored by VNG Corporation or Zalo. All trademarks and logos are the property of their respective owners.

---

## 📥 Installation

Pick the package for your distribution. Every release is built on the **oldest** release it supports and
installed on the oldest and newest one in CI.

| Distribution | Package | Supported releases & Qt6 handling |
|---|---|---|
| Ubuntu (and Mint, Pop!_OS, Zorin, elementary…) | `.deb` | Ubuntu **24.04 LTS+** (uses distro Qt6) |
| Fedora | `.rpm` | Fedora **43+** (uses distro Qt6) |
| NixOS / any distro with Nix | Nix flake | `nixos-unstable` (isolated Qt6 from `/nix/store`) |
| Ubuntu 22.04+, Debian 12+, openSUSE, Arch, others | AppImage | `glibc ≥ 2.35` (self-contained ~22 MB; bundles Qt 6.4 fallback when host Qt6 is absent) |

### Ubuntu 24.04+ (`.deb`)
```bash
# x86_64 (amd64)
wget https://github.com/cpfriend1721994/zalos/releases/latest/download/zalos_1.2.6-1~ubuntu24.04_amd64.deb
sudo apt install ./zalos_1.2.6-1~ubuntu24.04_amd64.deb

# ARM64 (aarch64)
wget https://github.com/cpfriend1721994/zalos/releases/latest/download/zalos_1.2.6-1~ubuntu24.04_arm64.deb
sudo apt install ./zalos_1.2.6-1~ubuntu24.04_arm64.deb
```

### Fedora 43+ (`.rpm`)
```bash
# x86_64
sudo dnf install https://github.com/cpfriend1721994/zalos/releases/latest/download/zalos-1.2.6-1.fc43.x86_64.rpm

# ARM64 (aarch64)
sudo dnf install https://github.com/cpfriend1721994/zalos/releases/latest/download/zalos-1.2.6-1.fc43.aarch64.rpm
```

### NixOS / Nix
```bash
nix run github:cpfriend1721994/zalos     # run without installing
nix profile install github:cpfriend1721994/zalos
```

### AppImage (portable, glibc ≥ 2.35)
```bash
# x86_64
wget https://github.com/cpfriend1721994/zalos/releases/latest/download/Zalos-1.2.6-x86_64.AppImage
chmod +x Zalos-1.2.6-x86_64.AppImage
./Zalos-1.2.6-x86_64.AppImage

# ARM64 (aarch64)
wget https://github.com/cpfriend1721994/zalos/releases/latest/download/Zalos-1.2.6-aarch64.AppImage
chmod +x Zalos-1.2.6-aarch64.AppImage
./Zalos-1.2.6-aarch64.AppImage
```
The AppImage (~22 MB) uses your host Qt 6 when available and automatically falls back to its bundled Qt 6.4 runtime on systems without Qt 6 (requiring only standard desktop libraries and `glibc ≥ 2.35`, e.g. Ubuntu 22.04+, Debian 12+, Fedora, openSUSE, Arch).

### Arch Linux & other distributions
No prebuilt native package is published for Arch Linux. Build it from source — clone this repository and
follow [Building from source](#️-building-from-source) — or just use the portable **AppImage** above.

> Every release ships **separate x86_64 and aarch64 (ARM64)** files for each format — download the one that
> matches your `uname -m`.

### Optional: calls
Voice and video calls run on Zalos's own C++ call engine (`zalos-call` and `zalos-call-audio`, in `libexec/zalos`),
which follows the call protocol of [zalo-for-linux](https://github.com/VN-Linux-Family/zalo-for-linux) (BSD-3-Clause).
Zalos has no Python or Node.js dependency at all:

- **Voice calls work out of the box** on `.deb`, `.rpm`, `Nix`, and the **AppImage** (the AppImage bundles a `libopus.so.0` fallback and connects directly to PulseAudio / PipeWire via `libpulse-simple.so.0`, which is already preinstalled on standard desktop Linux distributions; only minimal systems without PulseAudio/PipeWire client libraries need `libpulse0` on Ubuntu/Debian or `pulseaudio-libs` on Fedora).
- **Video calls** (seeing the other person's camera) additionally need **OpenH264** from your distribution (never bundled, for patent-licensing reasons): Ubuntu `sudo apt install libopenh264-7`, Fedora `sudo dnf install openh264`.

---

## 🛠️ Building from source

Builds run in containers, so the only prerequisites are `docker` (or `podman`) with Compose and Git.

```bash
git clone https://github.com/cpfriend1721994/zalos.git
cd zalos

docker compose run --rm build            # compile
docker compose run --rm test             # unit tests
docker compose run --rm gui-check        # headless GUI sanity check

docker compose run --rm package-appimage # dist/Zalos-*.AppImage
docker compose run --rm package-deb      # dist/zalos_*_amd64.deb
docker compose run --rm package-rpm      # dist/*.x86_64.rpm
docker compose run --rm package-nix      # dist/*-nixos.tar.gz
```

Pushing a semantic tag (`git tag v1.2.6 && git push origin v1.2.6`) builds the full package set and publishes
a GitHub Release.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the contributor workflow.

---

## 🤝 Contributing

Contributions are welcome. Please read the [Contributing Guidelines](CONTRIBUTING.md) and
[Code of Conduct](CODE_OF_CONDUCT.md) before opening a pull request.

---

## 📄 License

Distributed under the **MIT License**. See [LICENSE](LICENSE).
