<div align="center">

# 🐧 ArchLinuxARM Docker Builder

[![Buildx](https://img.shields.io/badge/docker-buildx-blue?logo=docker)](https://docs.docker.com/build/buildx/)
[![Architecture](https://img.shields.io/badge/arch-aarch64-brightgreen)](https://archlinuxarm.org/)
[![License](https://img.shields.io/badge/license-MIT-yellow)](./LICENSE)
[![GitHub Actions](https://img.shields.io/github/actions/workflow/status/devDucks/ArchLinuxARM/build.yml?logo=github)](https://github.com/devDucks/ArchLinuxARM/actions)
[![GHCR](https://img.shields.io/badge/GHCR-devDucks%2Farchlinuxarm-purple?logo=github)](https://ghcr.io/devDucks/archlinuxarm)

**Reproducible ArchLinuxARM builds for ARM boards and emulators — right from Docker.**

</div>

---

## 📦 Overview

This project automates building and exporting **ArchLinuxARM** root filesystems and Raspberry Pi images using **multi-stage Docker builds**.

You can build:
- 🧱 Minimal ArchLinuxARM base rootfs
- ⚙️ Full system with kernel, SSH, and systemd networking
- 🌌 **AstroArch** — a KDE-based astrophotography environment (KStars, INDI, PHD2, etc.)
- 💾 Ready-to-flash `.img` files for Raspberry Pi or for generic aarch64 devices

All builds are reproducible and run **entirely on x86_64** using QEMU emulation.

---

## 🚀 Quick Start

### Clone the repository
```bash
git clone https://github.com/devDucks/ArchLinuxARM.git
cd ArchLinuxARM
```

### Enable QEMU for cross-architecture builds
```bash
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
```

### Build the minimal ArchLinuxARM image
```bash
make build-minimal
```

### Build the full ArchLinuxARM (with kernel, SSH, networking)
```bash
make build-aarch64
```

### Build AstroArch (KDE + astrophotography tools)
```bash
make build-astroarch
```

Each build exports its rootfs tarball (`/archlinuxarm-aarch64-rootfs.tar` or `/astroarch-rootfs.tar`).

---

## 🧰 Make Targets

| Target | Description |
|--------|--------------|
| `build-minimal` | Minimal base ArchLinuxARM rootfs (`Dockerfile.base`). |
| `build-aarch64` | Full ArchLinuxARM with kernel, SSH, locale, DHCP. |
| `build-aarch64-rootfs` | Exports the aarch64 rootfs tarball. |
| `build-astroarch` | AstroArch desktop with KDE + INDI stack. |
| `build-astroarch-rootfs` | Exports the AstroArch rootfs tarball. |
| `prepare-rpi-img` | Creates a bootable Raspberry Pi image (`archarm-rpi-aarch64.img`). |

---

## 🧱 Image Structure

### 🔹 `dockerfiles/Dockerfile.base`
- Based on **Alpine**
- Installs `pacman`, `arch-install-scripts`
- Bootstraps `ArchLinuxARM aarch64` rootfs
- Exports `/archlinuxarm-aarch64-rootfs.tar`

### 🔹 `dockerfiles/Dockerfile.aarch64`
- Based on `archlinuxarm-basic`
- Sets mirrors and initializes pacman keys
- Installs: `glibc`, `linux-aarch64`, `nano`, `openssh`
- Configures `systemd-networkd` (DHCP)
- Enables SSH (`root/alarm`)
- Fixes locale (`locale.gen` rebuild)

### 🔹 `dockerfiles/Dockerfile.astroarch`
- Adds **AstroMatto** repository
- Tweaks pacman (`ILoveCandy`, disable timeout)
- Installs:
  - KDE Plasma desktop
  - KStars + Ekos
  - INDI drivers
  - PHD2 guiding
  - VNC tools (tigervnc)
  - XRDP to access the environment via RDP
- Exports `/astroarch-rootfs.tar`

### 🔹 `scripts/build_img.sh`
- Creates a bootable `.img` (`archarm-rpi-aarch64.img`)
- Partitions disk → `/boot` (FAT32), `/` (ext4)
- Copies rootfs
- Applies UUIDs, mount points, fsck, etc.

---

## 💾 Build an AstroArch Raspberry Pi Image

```bash
make prepare-rpi-img
```

The result is:
```
archarm-rpi-aarch64.img
```

You can now boot the `.img` just created using qemu, run `./scripts/start_qemu.sh`
you can then login into the system make your changes and `shutdown now`.
This will leave you with a ready to be flashed image wich includes your custom changes

Flash it to an SD card:
```bash
sudo dd if=archarm-rpi-aarch64.img of=/dev/sdX bs=4M status=progress
sync
```

Then insert the SD card into your Pi and boot — SSH will be ready via DHCP.

---

## 🔐 Default Credentials

| Image | User | Password | Notes |
|-------|------|----------|-------|
| ArchLinuxARM | root | alarm | SSH enabled by default |
|--------------|------|-------|------------------------|
| AstroArch | astronaut | astro | SSH enabled by default |

---



---

## 🌍 Mirror List

Mirrors used during build (`/etc/pacman.d/mirrorlist`):

```
Server = http://dk.mirror.archlinuxarm.org/$arch/$repo
Server = http://de3.mirror.archlinuxarm.org/$arch/$repo
Server = http://eu.mirror.archlinuxarm.org/$arch/$repo
Server = http://fl.us.mirror.archlinuxarm.org/$arch/$repo
```

You can modify mirrors in Dockerfiles or via build args.

---

## 🪐 AstroArch at a Glance

AstroArch is a preconfigured ArchLinuxARM environment for **astrophotography setups**.

Includes:
- 🪩 KDE Plasma Desktop
- 🌠 KStars + Ekos
- 🔭 INDI drivers
- 📷 PHD2 guiding
- 🖥️ Remote access via VNC or RDP

Built for **Raspberry Pi 5** observatories and **headless rigs**.

---

## 📁 Project Layout

```
├── dockerfiles/
│   ├── Dockerfile.base
│   ├── Dockerfile.aarch64
│   └── Dockerfile.astroarch
├── scripts/
│   └── build_img.sh
├── Makefile
└── README.md
```

---

## 🧾 License & Credits

- **License:** [MIT](./LICENSE)
- **Maintainers:** [devDucks](https://github.com/devDucks) 🦆
- **Based on:** [ArchLinuxARM](https://archlinuxarm.org/)
- **Inspired by:** [AstroArch Linux Distro](https://github.com/devDucks/AstroArch)

---

<div align="center">

> _“Build once, flash anywhere — the Arch way.”_

✨ Made with ❤️ by **devDucks**

</div>
