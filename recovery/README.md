# Recovery kit — reflash a working WFMU transmitter card fast

A full SD-card image is multiple GB and can't live in git. What lives here instead
is everything needed to get back on air quickly two different ways:

1. **Restore a saved image** (~15–20 min) — if you made a backup of a known-good card.
2. **Rebuild from a fresh Raspberry Pi OS install** (~30–40 min) — no image needed,
   just this repo.

Keep the actual `.img.gz` backup **off git** (it's large and in `.gitignore`). Store it
on your Mac, a USB stick, or cloud drive. This folder only holds the scripts + steps.

---

## A. Make a backup of the current, working card (do this once, now)

On the **Mac**, with the Pi powered off and its SD card in a reader:

```bash
diskutil list                       # find the card, e.g. /dev/disk4 (NOT disk0 — that's your Mac)
./backup_sdcard.sh disk4 ~/wfmu-known-good.img.gz
```

This produces a compressed image of the whole card. Label it with the date and stash it
somewhere safe. That single file is your "20-minute reflash."

Tip: shrink writes/size by backing up right after a clean setup, before logs pile up.

---

## B. Restore that image to a fresh (or corrupted) card

On the **Mac**, card in the reader:

```bash
diskutil list                       # confirm the target disk id
./restore_sdcard.sh disk4 ~/wfmu-known-good.img.gz
```

The script unmounts the card, writes the image, and syncs. Put the card in the Pi and
boot — it comes up exactly as the backup was, including the autostart services and
tuned 91.1 config. **Nothing else to do.**

WARNING: restore erases the target disk completely. The script forces you to type the
disk id and confirm, and refuses `disk0`, but double-check `diskutil list` yourself.

---

## C. Rebuild from scratch (no image — fresh Raspberry Pi OS)

Use this if you have no backup image, or want to build a newer OS card.

1. Flash **Raspberry Pi OS (Bookworm/Trixie, 64-bit)** with Raspberry Pi Imager.
   In the Imager's settings gear, pre-set: hostname `wfmu`, user `travis`, enable SSH,
   and your WiFi — so it boots reachable.
2. Boot the Pi, SSH in, then:

   ```bash
   git clone https://github.com/travishartman/WFMU-LOCAL-EVERYWHERE.git ~/WFMU-LOCAL-EVERYWHERE
   cd ~/WFMU-LOCAL-EVERYWHERE/recovery
   ./rebuild_from_scratch.sh
   ```

   That script enables I2C, installs all deps + the Python venv (via
   `../setup_si4713_env.sh`), and installs + enables the autostart services (via
   `../install_autostart.sh`).
3. Set the DAC audio source / Icecast relay — this piece is **not** in this repo; follow
   the relay setup in `now.md` (the `http://localhost:8000/wfmu.mp3` stream). The audio
   service depends on it.
4. Reboot to confirm it comes up broadcasting on 91.1 hands-off.

---

## Recommended hardening for a long unattended run

Do these once on the working card *before* you take the backup in step A, so the backup
already includes them:

- **Journal to RAM (protects the SD card from log-write wear/corruption):**
  ```bash
  sudo sed -i 's/^#\?Storage=.*/Storage=volatile/' /etc/systemd/journald.conf
  sudo systemctl restart systemd-journald
  ```
- **Use a solid 5V/2.5A+ supply and good cable** — brownouts are the top cause of the
  corruption that forces a reflash.
- After everything's verified working, **then** run `./backup_sdcard.sh` so your golden
  image is the hardened version.

---

## Files in this folder

- `backup_sdcard.sh` — Mac: dump a card to a compressed `.img.gz`.
- `restore_sdcard.sh` — Mac: write a `.img.gz` back to a card (destructive, guarded).
- `rebuild_from_scratch.sh` — Pi: turn a fresh Raspberry Pi OS install into a working
  transmitter using the repo's existing setup scripts.
