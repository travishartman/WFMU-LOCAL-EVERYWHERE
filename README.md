# WFMU-LOCAL-EVERYWHERE

Rebroadcast the WFMU stream as a low-power local FM signal from a Raspberry Pi,
using an SI4713 transmitter fed by a USB audio DAC. The whole chain starts
automatically on boot and is built to run unattended for weeks.

- **Device:** Raspberry Pi Zero 2 W, hostname `wfmu`, user `travis`
- **Repo on the Pi:** `/home/travis/WFMU-LOCAL-EVERYWHERE`
- **Broadcast frequency:** 91.1 MHz (station `WFMU`, RDS text "WFMU live")

---

## Signal chain

```
WFMU internet stream
      │  (stream_source.py)
      ▼
Icecast relay  http://localhost:8000/wfmu.mp3
      │  (play_usb_dac.sh → mpg123)
      ▼
USB DAC  hw:<auto>,0  ── 3.5mm cable ──► SI4713 line-in
                                              │  (si4713_bringup.sh over I2C sets carrier + RDS)
                                              ▼
                                         91.1 MHz FM  ──► antenna wire
```

Two independent paths run in parallel:

- **Tuning path (I2C):** `si4713.service` runs `si4713_bringup.sh` once at boot to
  set the carrier frequency, power, and RDS text on the SI4713.
- **Audio path (USB → analog):** `wfmu-audio.service` runs `play_usb_dac.sh`, which
  pipes the local Icecast relay through `mpg123` into the USB DAC.

These are deliberately decoupled: a slow or wedged transmitter bring-up must never
block or cancel audio, and vice versa. See "Resolved issues" for why this matters.

---

## Terminal-only hotkeys (1-5 source switching)

You can switch sources interactively from an SSH terminal on the Pi.

- `1` = WFMU live stream
- `2` = Rock'n'Soul Radio
- `3` = Give the Drummer Radio
- `4` = Sheena's Jungle Room Radio
- `5` = Spotify (Pi-side librespot receiver)

Important behavior:

- Hotkeys are **terminal-only**: they work only while the listener is running in
  that focused terminal session.
- Boot behavior is unchanged: the Pi still auto-starts key `1` (main WFMU) with
  zero input after reboot.

Run the listener:

```bash
sudo wfmu-radio-hotkeys
```

Inside the listener:

- `s` = status
- `q` = quit

### What each key does under the hood

- Keys `1-4`: stop Spotify service (if active), set `STREAM_URL` in
  `/etc/default/wfmu-audio`, restart `wfmu-audio.service`.
- Key `5`: stop `wfmu-audio.service`, start `librespot-wfmu.service`.

The switch helper command can also be run directly:

```bash
sudo wfmu-switch-source 1
sudo wfmu-switch-source 2
sudo wfmu-switch-source 3
sudo wfmu-switch-source 4
sudo wfmu-switch-source 5
sudo wfmu-switch-source status
```

Or use the short channel commands from anywhere (they auto-elevate):

```bash
wfmu1   # WFMU live
wfmu2   # Rock'n'Soul Radio
wfmu3   # Give the Drummer Radio
wfmu4   # Sheena's Jungle Room Radio
wfmu5   # Spotify
```

---

## Icecast relay mounts for keys 1-4

To keep switching consistent with the current localhost relay architecture,
configure all four relay mounts in Icecast:

- `/wfmu.mp3`
- `/rocknsoul.mp3`
- `/drummer.mp3`
- `/sheena.mp3`

Use `icecast-relay.xml.example` as the source stanzas and merge them under
`<icecast>` in `/etc/icecast2/icecast.xml`.

After editing:

```bash
sudo systemctl restart icecast2
```

Quick checks:

```bash
curl -I http://localhost:8000/wfmu.mp3
curl -I http://localhost:8000/rocknsoul.mp3
curl -I http://localhost:8000/drummer.mp3
curl -I http://localhost:8000/sheena.mp3
```

---

## Spotify key (5) requirements

Key `5` uses a Pi-side `librespot` service (Spotify Connect receiver). Your
desktop/mobile Spotify app acts as the remote control.

1. Install librespot on the Pi (package name varies by distro image).
2. Ensure `/etc/default/librespot-wfmu` has the desired device name and output settings.
3. Start key `5` with `sudo wfmu-switch-source 5` or via the hotkey listener.
4. In Spotify app, open "Connect to a device" and select the Pi device name.

If Spotify service fails, switching logic falls back to key `1`.

---

## First-time setup on the Pi

1. **Enable the I2C bus** (once). Uncomment in `/boot/firmware/config.txt`:
   ```
   dtparam=i2c_arm=on
   ```
   Reboot after editing.

2. **Install dependencies and the Python environment:**
   ```bash
   cd ~/WFMU-LOCAL-EVERYWHERE
   ./setup_si4713_env.sh
   ```
   This installs the APT packages (`i2c-tools`, `mpg123`, `alsa-utils`, GPIO
   backends, etc.), recreates the `.venv` with `--system-site-packages`, and
   installs `adafruit-blinka` + `adafruit-circuitpython-si4713`.

3. **Install autostart** (systemd units + login banner):
   ```bash
   bash install_autostart.sh
   ```
   Then reboot to verify, or start immediately:
   ```bash
   sudo systemctl start si4713.service wfmu-audio.service
   ```

> Run the installer with `bash install_autostart.sh` (not `sh`, not `./`). It uses
> bash-only syntax; running it under `sh`/dash produces `Bad substitution` and a
> broken banner path. See "Resolved issues."

---

## Autostart (systemd)

`install_autostart.sh` installs and enables two units, saved in `systemd/`:

### `si4713.service` — transmitter bring-up (oneshot)
- Runs `si4713_bringup.sh 91.1 WFMU "WFMU live"` once at boot, `RemainAfterExit=yes`.
- `TimeoutStartSec=120` caps runtime so a wedged chip can't stall boot.
- `Restart=on-failure` re-runs with a fresh reset pulse if the first attempt loses
  the reset-pulse race.
- `StartLimitIntervalSec`/`StartLimitBurst` live in `[Unit]` (not `[Service]`).

### `wfmu-audio.service` — audio feed (long-running)
- Runs `play_usb_dac.sh http://localhost:8000/wfmu.mp3 auto`.
- `After=sound.target icecast2.service` + `Wants=icecast2.service` so it starts
  after the relay. **If your relay unit is named something other than
  `icecast2.service`, edit those two lines** and `sudo systemctl daemon-reload`.
- `Restart=always` — reconnects if the relay isn't up yet, if the `wfmu.mp3` mount
  isn't populated yet, or if the stream drops later.

**To change the broadcast frequency:** edit the `ExecStart=` line in
`/etc/systemd/system/si4713.service`, then `sudo systemctl daemon-reload &&
sudo systemctl restart si4713.service`. The login banner reads the frequency back
from this unit, so it stays in sync automatically.

Check status any time:
```bash
./wfmu-status.sh
systemctl status si4713.service wfmu-audio.service
journalctl -u si4713.service -u wfmu-audio.service -b
```

### Powering down / restarting
Always shut the Pi down cleanly before pulling power — yanking the cord risks
corrupting the SD card:

```bash
sudo shutdown -h now     # power off now (equivalent: sudo poweroff)
sudo reboot              # restart now
sudo shutdown -h +5      # power off in 5 minutes
sudo shutdown -c         # cancel a pending scheduled shutdown
```

After `shutdown -h now` the Pi halts within a few seconds; wait for the green
activity LED to stop blinking before unplugging. On next power-up everything comes
back automatically — no commands needed.


---

## Login status banner

Every interactive SSH login prints an on-air banner (WFMU ASCII art + service
states), generated by `wfmu-status.sh`. `install_autostart.sh` installs it **two**
ways for robustness:

1. **`~/.bashrc`** — a guarded `case $- in *i*)` block. This is the reliable path on
   Raspberry Pi OS Lite.
2. **Dynamic MOTD** (`/etc/update-motd.d/99-wfmu`) — works only on images whose
   login PAM stack is wired for `pam_motd motd=/run/motd.dynamic`.

The installer is idempotent — re-running it won't duplicate the `.bashrc` block.

Run the banner by hand any time: `./wfmu-status.sh` (or `sh wfmu-status.sh` if the
exec bit is missing).

---

## Deploy workflow

Edit on the Mac, push, then pull on the Pi — over a direct SSH session or a
[Raspberry Pi Connect](https://connect.raspberrypi.com) remote shell. The repo is
public, so `clone`/`pull` work over plain HTTPS with no credentials on the Pi.

```bash
# Mac — edit, then:
git add -A && git commit -m "..." && git push

# Pi:
cd ~/WFMU-LOCAL-EVERYWHERE && git pull && bash install_autostart.sh
```

First clone on a fresh card:
```bash
git clone https://github.com/travishartman/WFMU-LOCAL-EVERYWHERE.git
```

### Commit from the Mac, not the Pi
Commits are **gpg-signed**, which fails in non-interactive shells. Always
`git commit`/`git push` from the Mac. The Pi only ever does `git pull`; its git
identity / GitHub login state is irrelevant as long as it never commits or pushes.

### Executable-bit / "local changes would be overwritten" conflicts
`chmod +x` on the Pi creates a mode-change diff that blocks the next `git pull`
("Your local changes to the following files would be overwritten by merge").
Discard the local mode change and pull:
```bash
git checkout -- install_autostart.sh   # or the named file
git pull
```
Running scripts with `bash <script>` / `sh <script>` avoids needing the exec bit at
all, so it avoids creating these diffs. To set the bit **in git** once (from the
Mac) so scripts arrive executable:
```bash
git update-index --chmod=+x install_autostart.sh wfmu-status.sh play_usb_dac.sh \
  si4713_bringup.sh setup_si4713_env.sh
git commit -m "Mark scripts executable" && git push
```

---

## Resolved issues (field notes)

| Symptom | Cause | Fix |
|---|---|---|
| No audio after reboot; `wfmu-audio` shows `inactive (dead)` | A wedged SI4713 made the first I2C attempt hang ~9 min, blew the boot job timeout, and the queued audio job got **cancelled** (so `Restart=always` never fired). | `TimeoutStartSec=120` on `si4713.service`; removed the si4713 dependency from `wfmu-audio.service` so audio starts independently. |
| Carrier up but audio nearly silent | USB DAC's only mixer control ("Headphone") resets to ~30/100 on boot, and `alsactl` doesn't restore it reliably for USB cards. | `play_usb_dac.sh` forces the level to 100% every start (`HEADPHONE_LEVEL` overridable), with a fallback to the first mixer control if "Headphone" is absent. |
| Audio breaks when the DAC's card number changes | USB audio cards can shuffle ALSA index across boots; `hw:1,0` was fragile. | `play_usb_dac.sh auto` finds the USB card by name in `/proc/asound/cards` and builds `hw:<card>,0`. |
| First-boot "Connection refused" / "404 File Not Found" | Icecast relay/mount not populated yet when audio first tries. | Expected and self-healing: `Restart=always` reconnects (typically within ~40s). Ordering `After=icecast2.service` reduces first-try failures. |
| `install_autostart.sh: Bad substitution` | Ran under `sh`/dash; the script uses bash-only `${BASH_SOURCE[0]}`. `HERE` came out empty and the banner path broke. | Run with `bash install_autostart.sh`. |
| No status banner on SSH login | Pi OS Lite's login PAM stack doesn't run `/etc/update-motd.d/`; only the static `/etc/motd` shows. | Banner is also sourced from `~/.bashrc` (interactive-only guard), which always runs on login. |
| `git pull` blocked by "local changes would be overwritten" | `chmod +x` on the Pi created a mode-change diff. | `git checkout -- <file>` then `git pull`; or set the exec bit in git from the Mac (see above). |
| Commit/push fails on the Pi | gpg signing prompts can't be answered non-interactively. | Commit and push from the Mac only; the Pi pulls. |

> Do **not** run `pinctrl set 5 op dh` before `si4713_bringup.sh`. The Adafruit
> library drives the RST line (GPIO5) itself; a manual override causes
> "Timeout waiting for SI4713 to respond". Use `pinctrl` only to confirm wiring via
> `i2cdetect -y 1` (expect a device at `0x63`), then reboot and bring up cleanly.

---

## Recovery kit

`recovery/` holds everything to get back on air fast without storing a multi-GB
image in git (see `recovery/README.md`):

- `backup_sdcard.sh` / `restore_sdcard.sh` — Mac-side `dd` backup/restore to
  `*.img.gz` (kept out of git via `.gitignore`).
- `rebuild_from_scratch.sh` — rebuild from a fresh Raspberry Pi OS install using
  this repo's setup/install scripts.

Make a known-good backup once, right after a clean setup:
```bash
# Mac, Pi card in a reader:
diskutil list
./recovery/backup_sdcard.sh disk4 ~/wfmu-known-good.img.gz
```

---

## Hardware FM mode (SI4713) reference

The repo includes the scripts the hardware plan calls for:

- `./setup_si4713_env.sh` — install packages, (re)create the venv, install Python deps.
- `.venv/bin/python si4713_control.py 91.1 --station WFMU --radio-text "WFMU live"` —
  configure frequency, power, and RDS over I2C.
- `./si4713_bringup.sh [FREQ] [STATION] [RADIO_TEXT]` — boot-time bring-up with one
  automatic retry for the reset-pulse race (this is what the service runs).
- `./play_usb_dac.sh [stream_url] [alsa_device]` — feed the DAC. `alsa_device`
  defaults to `auto`; pass `hw:N,0` to force a device or `default` for the ALSA sink.

Wiring is documented in `../later-hardware.md`: SDA on Pi pin 3, SCL on pin 5, RST on
GPIO5/pin 29, CS tied high for I2C address `0x63`, and the DAC's 3.5mm output into the
SI4713 line-in.
