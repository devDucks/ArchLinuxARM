#!/usr/bin/env bash
set -euo pipefail

# --- settings ---
IMG=${IMG:-archarm-rpi-aarch64.img}
SIZE=${SIZE:-4G}          # total image size
BOOT_MB=${BOOT_MB:-768}   # FAT32 /boot size in MiB
ROOT_LABEL=${ROOT_LABEL:-ALARM_ROOT}
BOOT_LABEL=${BOOT_LABEL:-ALARM_BOOT}
ROOTFS_TAR=${ROOTFS_TAR:-rootfs.tar}

# sanity
[ -f "$ROOTFS_TAR" ] || { echo "Missing $ROOTFS_TAR"; exit 1; }

# tools needed: sfdisk, losetup, mkfs.vfat, mkfs.ext4, tar, rsync or cp -a
command -v sfdisk >/dev/null
command -v losetup >/dev/null

# --- create sparse disk file ---
truncate -s "$SIZE" "$IMG"

# --- partition table: 1MiB align, 768MiB FAT32 boot, rest ext4 root ---
BOOT_START=2048                               # 1MiB (512b sectors)
BOOT_SIZE=$(( BOOT_MB * 2048 ))               # sectors (MiB * 2048)
sfdisk "$IMG" <<EOF
label: dos
unit: sectors
${IMG}1 : start=${BOOT_START}, size=${BOOT_SIZE}, type=c
${IMG}2 : start=$((BOOT_START+BOOT_SIZE)), type=83
EOF

# --- map loop with partitions ---
LOOP=$(sudo losetup --find --show --partscan "$IMG")
BOOT_DEV=${LOOP}p1
ROOT_DEV=${LOOP}p2
PARTUUID=$(sudo blkid -s PARTUUID -o value "$ROOT_DEV")

# --- mkfs ---
sudo mkfs.vfat -F 32 -n "$BOOT_LABEL" "$BOOT_DEV"
sudo mkfs.ext4 -F -L "$ROOT_LABEL" "$ROOT_DEV"

BOOT_UUID=$(sudo blkid -s UUID -o value "$BOOT_DEV")
ROOT_UUID=$(sudo blkid -s UUID -o value "$ROOT_DEV")

# --- mount ---
sudo mkdir -p /mnt/arch-root /mnt/arch-boot
sudo mount "$ROOT_DEV" /mnt/arch-root
sudo mkdir -p /mnt/arch-root/boot
sudo mount "$BOOT_DEV" /mnt/arch-boot

# --- extract rootfs (preserve xattrs/owners) ---
sudo tar --numeric-owner -xpf "$ROOTFS_TAR" -C /mnt/arch-root

# --- move/copy boot files to the FAT32 partition ---
# Official instructions literally "move root/boot/* to boot" when using their tarball.
# We do the equivalent from our extracted rootfs.
if [ -d /mnt/arch-root/boot ] && [ -n "$(ls -A /mnt/arch-root/boot)" ]; then
  sudo cp -a /mnt/arch-root/boot/* /mnt/arch-boot/
fi

# --- minimal boot config depending on strategy ---
# If you installed linux-rpi (+ raspberrypi-bootloader), firmware boots kernel*.img via config.txt/cmdline.txt
if [ -f /mnt/arch-boot/kernel8.img ]; then
  printf 'arm_64bit=1\nenable_uart=1\n' | sudo tee /mnt/arch-boot/config.txt >/dev/null
  # root= by PARTUUID (safest). Discover it:
  sudo tee /mnt/arch-boot/cmdline.txt >/dev/null <<EOF
console=serial0,115200 console=ttyAMA0,115200 root=PARTUUID=${PARTUUID} rw rootwait
EOF
fi

# If you installed linux-aarch64 + uboot-raspberrypi, ensure extlinux.conf exists
if [ -d /mnt/arch-boot/extlinux ]; then
  :
elif [ -f /mnt/arch-boot/u-boot.bin ] || [ -f /mnt/arch-root/boot/u-boot.bin ]; then
  sudo install -d /mnt/arch-boot/extlinux
  sudo tee /mnt/arch-boot/extlinux/extlinux.conf >/dev/null <<EOF
DEFAULT arch
MENU TITLE Arch Linux ARM
TIMEOUT 3

LABEL arch
  LINUX /Image
  INITRD /initramfs-linux.img
  FDTDIR /dtbs
  APPEND root=PARTUUID=${PARTUUID} rw rootwait console=ttyAMA0,115200 console=serial0,115200
EOF
fi

# --- fstab (Pi 4 aarch64 note: ALARM docs use mmcblk1) ---
# Use PARTUUIDs so device names don’t matter.
sudo tee /mnt/arch-root/etc/fstab <<EOF
UUID=${ROOT_UUID}  /      ext4   defaults,noatime  0 1
UUID=${BOOT_UUID}  /boot  vfat   defaults,noatime  0 2
EOF

sync

# --- unmount & detach ---
sudo umount /mnt/arch-boot || true
sudo umount /mnt/arch-root || true
sudo losetup -d "$LOOP"

echo "OK: ${IMG} is ready."
