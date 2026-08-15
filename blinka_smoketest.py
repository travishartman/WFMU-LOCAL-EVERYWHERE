#!/usr/bin/env python3
"""Minimal Raspberry Pi Blinka smoke test for the SI4713 setup path."""

from __future__ import annotations

import sys


def main() -> int:
    try:
        import board
        import busio
        import digitalio
    except ImportError as exc:
        print(f"Blinka import failed: {exc}", file=sys.stderr)
        return 1

    print("Blinka imports ok")

    try:
        pin = digitalio.DigitalInOut(board.D5)
        pin.deinit()
        print("Digital IO ok (board.D5)")
    except Exception as exc:  # pragma: no cover - hardware dependent
        print(f"Digital IO failed: {exc}", file=sys.stderr)
        return 1

    try:
        i2c = busio.I2C(board.SCL, board.SDA)
        i2c.deinit()
        print("I2C object creation ok")
    except Exception as exc:  # pragma: no cover - hardware dependent
        print(f"I2C setup failed: {exc}", file=sys.stderr)
        return 1

    print("Smoke test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())