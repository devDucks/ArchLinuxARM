#!/usr/bin/env bash
# Sanity-check a built AstroArch .img without booting it.
#
# The partitions are mounted read-only by byte offset rather than through
# `losetup --partscan`, because partition device nodes (/dev/loopNp1) are not
# reliably created on GitHub-hosted runners.
#
# Usage: ./scripts/verify_img.sh [image]
#
# Exits non-zero if a check marked FAIL does not pass. Checks marked WARN are
# reported but do not fail the run.

set -euo pipefail

IMG=${1:-archarm-rpi-aarch64.img}
ROOT_MNT=${ROOT_MNT:-/mnt/verify-root}
BOOT_MNT=${BOOT_MNT:-/mnt/verify-boot}

[ -f "$IMG" ] || { echo "Missing $IMG"; exit 1; }

failures=0
warnings=0

pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }
warn() { printf '  warn  %s\n' "$1"; warnings=$((warnings + 1)); }

check() { # check <description> <path relative to root>
  if sudo test -e "$ROOT_MNT/$2"; then pass "$1"; else fail "$1 (missing $2)"; fi
}

check_warn() {
  if sudo test -e "$ROOT_MNT/$2"; then pass "$1"; else warn "$1 (missing $2)"; fi
}

cleanup() {
  sudo umount "$BOOT_MNT" 2>/dev/null || true
  sudo umount "$ROOT_MNT" 2>/dev/null || true
}
trap cleanup EXIT

# --- partition geometry, straight from the partition table ---
# partx prints plain sector numbers, which avoids parsing sfdisk's padded
# `start=   2048,` syntax.
geom=$(partx -g -o NR,START,SECTORS "$IMG")
BOOT_START=$(echo "$geom" | awk '$1 == 1 { print $2 }')
BOOT_SIZE=$(echo "$geom" | awk '$1 == 1 { print $3 }')
ROOT_START=$(echo "$geom" | awk '$1 == 2 { print $2 }')

if [ -z "$BOOT_START" ] || [ -z "$BOOT_SIZE" ] || [ -z "$ROOT_START" ]; then
  echo "Could not read the partition table of $IMG"
  partx -o NR,START,SECTORS "$IMG" || true
  exit 1
fi

echo "== partition table =="
echo "  boot: start=${BOOT_START}s size=${BOOT_SIZE}s ($(( BOOT_SIZE / 2048 )) MiB)"
echo "  root: start=${ROOT_START}s"

sudo mkdir -p "$ROOT_MNT" "$BOOT_MNT"
sudo mount -o ro,loop,offset=$(( ROOT_START * 512 )) "$IMG" "$ROOT_MNT"
sudo mount -o ro,loop,offset=$(( BOOT_START * 512 )),sizelimit=$(( BOOT_SIZE * 512 )) "$IMG" "$BOOT_MNT"

echo
echo "== filesystem usage =="
df -h "$ROOT_MNT" "$BOOT_MNT" | sed 's/^/  /'

echo
echo "== boot partition =="
if sudo test -e "$BOOT_MNT/kernel8.img" || sudo test -e "$BOOT_MNT/Image"; then
  pass "a kernel is present"
else
  fail "no kernel8.img or Image on the boot partition"
fi
if sudo test -e "$BOOT_MNT/config.txt"; then pass "config.txt"; else fail "config.txt"; fi
if sudo test -e "$BOOT_MNT/cmdline.txt"; then
  cmdline=$(sudo cat "$BOOT_MNT/cmdline.txt")
  echo "  cmdline: $cmdline"
  # build_img.sh rewrites root= with the real PARTUUID; astroarch_build.sh
  # leaves the QEMU /dev/vda2 UUID behind, which would not boot on a Pi.
  part_uuid=$(printf '%s' "$cmdline" | sed -n 's/.*root=PARTUUID=\([^ ]*\).*/\1/p')
  if [ -n "$part_uuid" ]; then
    pass "cmdline.txt uses root=PARTUUID=$part_uuid"
  else
    fail "cmdline.txt does not set root=PARTUUID= (found: $cmdline)"
  fi
else
  fail "cmdline.txt"
fi
if sudo test -d "$BOOT_MNT/overlays"; then pass "device tree overlays"; else warn "no overlays/ directory"; fi

echo
echo "== users =="
for u in astronaut astronaut-kiosk; do
  if sudo grep -q "^$u:" "$ROOT_MNT/etc/passwd"; then pass "user $u"; else fail "user $u"; fi
done
if sudo grep -q "^astronaut:" "$ROOT_MNT/etc/shadow" && \
   [ "$(sudo awk -F: '/^astronaut:/ {print $2}' "$ROOT_MNT/etc/shadow")" != "" ]; then
  pass "astronaut has a password set"
else
  fail "astronaut has no password"
fi
check "astronaut home"        home/astronaut
check "oh-my-zsh"             home/astronaut/.oh-my-zsh
check "astroarch checkout"    home/astronaut/.astroarch

echo
echo "== system identity =="
hostname=$(sudo cat "$ROOT_MNT/etc/hostname" 2>/dev/null || echo "")
if [ "$hostname" = "astroarch" ]; then pass "hostname=astroarch"; else fail "hostname is '$hostname'"; fi
if sudo grep -q astroarch "$ROOT_MNT/etc/hosts"; then pass "/etc/hosts"; else fail "/etc/hosts has no astroarch entry"; fi
if sudo grep -q " / " "$ROOT_MNT/etc/fstab" && sudo grep -q " /boot " "$ROOT_MNT/etc/fstab"; then
  pass "fstab has / and /boot"
else
  fail "fstab is incomplete"
fi
echo "  fstab:"; sudo sed 's/^/    /' "$ROOT_MNT/etc/fstab"

version=""
if sudo test -e "$ROOT_MNT/home/astronaut/.astroarch.version"; then
  version=$(sudo cat "$ROOT_MNT/home/astronaut/.astroarch.version" 2>/dev/null | tr -d '[:space:]')
  pass "AstroArch version ${version:-unknown}"
  printf '%s' "${version:-dev}" > astroarch.version
else
  warn "no .astroarch.version"
  printf 'dev' > astroarch.version
fi

echo
echo "== boot target =="
default_target=$(sudo readlink "$ROOT_MNT/etc/systemd/system/default.target" 2>/dev/null || echo "")
if [ -z "$default_target" ]; then
  # No override means systemd falls back to its compiled-in default, which is
  # graphical.target on Arch. Worth flagging rather than failing.
  warn "default.target is not overridden; systemd's built-in default applies"
else
  case "$default_target" in
    *graphical.target) pass "default.target -> graphical.target" ;;
    *) warn "default.target -> $default_target (SDDM will not start)" ;;
  esac
fi

echo
echo "== enabled units =="
for unit in graphical.target.wants/sddm.service \
            multi-user.target.wants/NetworkManager.service \
            multi-user.target.wants/xrdp.service \
            multi-user.target.wants/xrdp-sesman.service \
            multi-user.target.wants/smb.service \
            multi-user.target.wants/chronyd.service \
            multi-user.target.wants/novnc.service \
            multi-user.target.wants/resize_once.service; do
  link="$ROOT_MNT/etc/systemd/system/$unit"
  if sudo test -L "$link"; then
    target=$(sudo readlink "$link")
    # These symlinks point at absolute paths inside the image, so they have to
    # be resolved against the mount point and not against the host root.
    case "$target" in
      /*) resolved="$ROOT_MNT$target" ;;
      *)  resolved="$(dirname "$link")/$target" ;;
    esac
    if sudo test -e "$resolved"; then
      pass "$unit"
    else
      # An enabled unit whose target file does not exist means the package
      # providing it was never installed; systemd will log a failure at boot.
      warn "$unit is enabled but dangling -> $target"
    fi
  else
    warn "$unit is not enabled"
  fi
done
if sudo test -e "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/sshd.service"; then
  pass "sshd.service"
else
  warn "sshd.service is not enabled"
fi

echo
echo "== astrophotography stack =="
check "KStars"        usr/bin/kstars
check "PHD2"          usr/bin/phd2
check "indiserver"    usr/bin/indiserver
check "solve-field"   usr/bin/solve-field
check_warn "noVNC"    usr/share/webapps/novnc
check_warn "x0vncserver" usr/bin/x0vncserver

idx_dir="$ROOT_MNT/home/astronaut/.local/share/kstars/astrometry"
if sudo test -d "$idx_dir"; then
  n=$(sudo find "$idx_dir" -name 'index-*.fits' | wc -l)
  bytes=$(sudo du -sm "$idx_dir" | cut -f1)
  if [ "$n" -ge 100 ]; then
    pass "astrometry indexes: $n files, ${bytes} MiB"
  else
    fail "only $n astrometry index files (expected >= 100)"
  fi
else
  fail "no astrometry index directory"
fi

echo
echo "== desktop =="
check      "SDDM config"   etc/sddm.conf.d/kde_settings.conf
check_warn "Plasma X11"    usr/share/xsessions/plasmax11.desktop
check_warn "xorg.conf"     etc/X11/xorg.conf
check_warn "AstroArch look-and-feel" usr/share/plasma/look-and-feel/astroarch

echo
echo "== summary =="
echo "  failures: $failures"
echo "  warnings: $warnings"
[ "$failures" -eq 0 ] || { echo "Image verification FAILED"; exit 1; }
echo "Image verification passed."
