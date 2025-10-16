#!/usr/bin/env bash

IMG=archarm-rpi-aarch64.img
LOOP=$(sudo losetup --find --show --partscan "$IMG")
ROOT_UUID=$(sudo blkid -s PARTUUID -o value "${LOOP}p2")
BOOT_UUID=$(sudo blkid -s PARTUUID -o value "${LOOP}p1")
KERNEL=/mnt/arch-boot/Image
sudo mount "${LOOP}p1" /mnt/arch-boot
sudo mount "${LOOP}p2" /mnt/arch-root

qemu-system-aarch64 \
  -M virt -cpu max -m 8192 -display none \
  -kernel "$KERNEL" \
  -drive file="$IMG" \
  -serial stdio -monitor none \
  -nic user,model=virtio-net-pci,hostfwd=tcp::2222-:22 \
  -append "earlycon=pl011,0xfe201000 console=ttyAMA0,115200 root=PARTUUID=${ROOT_UUID} rootfstype=ext4 rw rootwait fsck.repair=yes"

sudo umount /mnt/arch-boot
sudo umount /mnt/arch-root
sudo losetup -D
