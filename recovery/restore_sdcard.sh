#!/bin/sh
# Restore a compressed image back onto an SD card (run on macOS).
#
# Usage: ./restore_sdcard.sh <disk-id> <input.img.gz>
#   e.g. ./restore_sdcard.sh disk4 ~/wfmu-known-good.img.gz
#
# Find <disk-id> with: diskutil list   (pick the SD card, NOT disk0 = your Mac)
#
# DESTRUCTIVE: this ERASES the target card and writes the image over it.

set -eu

disk="${1:?usage: restore_sdcard.sh <disk-id> <input.img.gz>  (e.g. disk4 ~/wfmu.img.gz)}"
img="${2:?usage: restore_sdcard.sh <disk-id> <input.img.gz>}"

disk="${disk#/dev/}"

if [ "$disk" = "disk0" ]; then
  echo "Refusing to write disk0 — that is almost certainly your Mac's internal drive." >&2
  exit 1
fi

if [ ! -f "$img" ]; then
  echo "Image not found: $img" >&2
  exit 1
fi

if ! diskutil info "$disk" >/dev/null 2>&1; then
  echo "No such disk: $disk. Run 'diskutil list' to find the SD card id." >&2
  exit 1
fi

echo "TARGET /dev/$disk will be COMPLETELY ERASED and overwritten with:"
echo "  $img"
echo
diskutil info "$disk" | grep -E 'Device / Media Name|Disk Size|Removable Media|Protocol' || true
echo
printf 'This ERASES /dev/%s. Type the disk id (%s) to confirm: ' "$disk" "$disk"
read -r confirm
[ "$confirm" = "$disk" ] || { echo "Mismatch — aborted."; exit 1; }

echo "Unmounting $disk..."
diskutil unmountDisk "/dev/$disk"

echo "Writing image -> /dev/r$disk (10-20 min; Ctrl-T shows progress)..."
if command -v pv >/dev/null 2>&1; then
  gzip -dc "$img" | pv | sudo dd of="/dev/r$disk" bs=4m
else
  gzip -dc "$img" | sudo dd of="/dev/r$disk" bs=4m
fi

sync
echo "Ejecting..."
diskutil eject "/dev/$disk" || true

echo
echo "Done. Put the card in the Pi and boot — it restores to the backed-up state,"
echo "including autostart services and the tuned 91.1 config."
