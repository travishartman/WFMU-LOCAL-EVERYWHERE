# WFMU-LOCAL-EVERYWHERE

Deploy target: Raspberry Pi Zero 2 W, hostname `wfmu`.

## Hardware FM mode

When the SI4713 hardware module arrives, the repo includes the two scripts the
hardware plan calls for:

- `./setup_si4713_env.sh` installs the Raspberry Pi OS packages, recreates the project virtualenv with system GPIO packages available, and installs the Python dependencies needed by the control script.
- `.venv/bin/python blinka_smoketest.py` verifies that Blinka imports, digital I/O, and I2C object creation work on the Pi before the SI4713 is wired.
- Create a project virtualenv on the Pi before using the control script: `sudo apt-get install -y python3-venv i2c-tools libgpiod-dev python3-libgpiod python3-rpi.gpio python3-lgpio && python3 -m venv .venv --system-site-packages && . .venv/bin/activate && pip install adafruit-blinka adafruit-circuitpython-si4713`.
- `.venv/bin/python si4713_control.py 98.3 --station WFMU --radio-text "WFMU live"` configures frequency, power, and optional RDS metadata over I2C.
- `./play_usb_dac.sh` plays the local Icecast relay (`http://localhost:8000/wfmu.mp3`) through the ALSA default output, or `./play_usb_dac.sh http://localhost:8000/wfmu.mp3 hw:1,0` to force a specific USB DAC device.

The SI4713 control script expects the wiring documented in `../later-hardware.md`: SDA on Pi pin 3, SCL on pin 5, reset on GPIO5/pin 29, and the module address-select pin tied high to use I2C address `0x63`.

## Deploy workflow

Push to this repo from a laptop, then pull on the Pi — either over a direct SSH session or via a [Raspberry Pi Connect](https://connect.raspberrypi.com) remote shell:

```
git clone https://github.com/travishartman/WFMU-LOCAL-EVERYWHERE.git
```

or, once already cloned:

```
git pull
```

No credentials are needed on the Pi side since the repo is public — `clone`/`pull` work over plain HTTPS.
