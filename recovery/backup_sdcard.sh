#!/bin/sh
# Back up a Raspberry Pi SD card to a compressed image (run on macOS).
#
# Usage: ./backup_sdcard.sh <disk-id> <output.img.gz>
#   e.g. ./backup_sdcard.sh disk4 ~/wfmu-known-good.img.gz
#
# Find <disk-id> with: diskutil list   (pick the SD card, NOT disk0 = your Mac)
#
# Produces a gzip-compressed whole-card image you can later write back with
# restore_sdcard.sh. Store the .img.gz somewhere safe and OFF git (it's large).

set -eu

disk="${1:?usage: backup_sdcard.sh <disk-id> <output.img.gz>  (e.g. disk4 ~/wfmu.img.gz)}"
out="${2:?usage: backup_sdcard.sh <disk-id> <output.img.gz>}"

# Normalize: accept "disk4" or "/dev/disk4".
disk="${disk#/dev/}"

if [ "$disk" = "disk0" ]; then
  echo "Refusing to read disk0 — that is almost certainly your Mac's internal drive." >&2
  exit 1
fi

if ! diskutil info "$disk" >/dev/null 2>&1; then
  echo "No such disk: $disk. Run 'diskutil list' to find the SD card id." >&2
  exit 1
fi

echo "About to image /dev/$disk :"
diskutil info "$disk" | grep -E 'Device / Media Name|Disk Size|Removable Media|Protocol' || true
printf 'Read this card to %s ? Type YES to continue: ' "$out"
read -r ans
[ "$ans" = "YES" ] || { echo "Aborted."; exit 1; }

echo "Unmounting $disk (card stays inserted)..."
diskutil unmountDisk "/dev/$disk"

# /dev/rdiskN is the raw device — much faster than /dev/diskN.
echo "Reading card -> $out (this can take 10-20 min; Ctrl-T shows progress)..."
if command -v pv >/dev/null 2>&1; then
  # Size in bytes for a progress bar.
  size=$(diskutil info "$disk" | awk -F'[()]' '/Disk Size/ {print $2}' | awk '{print $1}')
  sudo dd if="/dev/r$disk" bs=4m | pv ${size:+-s "$size"} | gzip > "$out"
else
  sudo dd if="/dev/r$disk" bs=4m | gzip > "$out"
fi

sync
echo
echo "Done. Backup written to: $out"
echo "Keep this file off git and somewhere safe — it is your fast-reflash image."
