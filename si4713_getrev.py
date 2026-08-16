#!/usr/bin/env python3
"""Read the SI4713's GET_REV identity over I2C to confirm the chip.

A genuine SI4713 reports part number 13. This resets + powers up the chip via
the Adafruit library (so GPIO5/RST is driven correctly), then issues the raw
GET_REV command (0x10) on the I2C bus and decodes the response.

Run in the project venv on the Pi:
    .venv/bin/python si4713_getrev.py
    .venv/bin/python si4713_getrev.py --reset-pin D5
"""

from __future__ import annotations

import argparse
import sys
import time

_GET_REV = 0x10
_ADDR = 0x63  # CS tied high


def main() -> int:
    parser = argparse.ArgumentParser(description="Confirm SI4713 identity via GET_REV.")
    parser.add_argument(
        "--reset-pin",
        default="D5",
        help="Blinka board pin wired to SI4713 RST. Default: D5 (Pi GPIO5 / pin 29).",
    )
    args = parser.parse_args()

    try:
        import adafruit_si4713
        import board
        import busio
        import digitalio
    except ImportError as exc:
        print(f"Missing dependency (run inside the venv): {exc}", file=sys.stderr)
        return 1

    try:
        reset_pin = getattr(board, args.reset_pin)
    except AttributeError:
        print(f"Unknown board pin: {args.reset_pin}", file=sys.stderr)
        return 1

    i2c = busio.I2C(board.SCL, board.SDA)
    reset = digitalio.DigitalInOut(reset_pin)

    try:
        # Constructing the library object drives RST and powers the chip up.
        adafruit_si4713.SI4713(i2c, reset=reset)

        while not i2c.try_lock():
            time.sleep(0.01)
        try:
            i2c.writeto(_ADDR, bytes([_GET_REV]))
            time.sleep(0.01)
            resp = bytearray(9)
            i2c.readfrom_into(_ADDR, resp)
        finally:
            i2c.unlock()

        part_number = resp[1]
        fw_major = resp[2]
        fw_minor = resp[3]
        chip_rev = resp[8]

        print(f"Part number: {part_number}  (expect 13 for SI4713)")
        print(f"Firmware:    {fw_major}.{fw_minor}")
        print(f"Chip rev:    {chip_rev}")
        if part_number == 13:
            print("=> Confirmed: this is an SI4713.")
            return 0
        print("=> WARNING: part number is not 13 — not the expected SI4713.")
        return 2
    except Exception as exc:  # pragma: no cover - hardware dependent
        print(f"Failed to read SI4713 revision: {exc}", file=sys.stderr)
        return 1
    finally:
        reset.deinit()
        i2c.deinit()


if __name__ == "__main__":
    raise SystemExit(main())
