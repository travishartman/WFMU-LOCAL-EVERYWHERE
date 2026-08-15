#!/usr/bin/env python3
"""Configure an SI4713 FM transmitter over the Raspberry Pi's I2C bus."""

from __future__ import annotations

import argparse
import sys


def _parse_frequency_khz(raw_value: str) -> int:
    """Accept MHz or kHz input and normalize to SI4713-compatible kHz."""
    try:
        if "." in raw_value:
            frequency_khz = round(float(raw_value) * 1000)
        else:
            parsed_int = int(raw_value)
            frequency_khz = parsed_int * 1000 if parsed_int < 1000 else parsed_int
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"invalid frequency: {raw_value}") from exc

    if not 76000 <= frequency_khz <= 108000:
        raise argparse.ArgumentTypeError("frequency must be between 76.0 and 108.0 MHz")
    if frequency_khz % 50 != 0:
        raise argparse.ArgumentTypeError("frequency must land on a 50kHz step, e.g. 98.3 or 98300")
    return frequency_khz


def _ascii_bytes(value: str | None, label: str, limit: int) -> bytes | None:
    if value is None:
        return None
    try:
        encoded = value.encode("ascii")
    except UnicodeEncodeError as exc:
        raise SystemExit(f"{label} must be plain ASCII for RDS broadcast") from exc
    if len(encoded) > limit:
        raise SystemExit(f"{label} must be {limit} bytes or fewer")
    return encoded


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Set SI4713 frequency, transmit power, and optional RDS metadata.",
    )
    parser.add_argument(
        "freq",
        type=_parse_frequency_khz,
        help="Transmit frequency in MHz or kHz, for example 98.3 or 98300.",
    )
    parser.add_argument(
        "--power",
        type=int,
        default=115,
        help="Transmit power in dBuV (0 to disable, otherwise 88-115). Default: 115.",
    )
    parser.add_argument(
        "--reset-pin",
        default="D5",
        help="Blinka board pin name wired to SI4713 RST. Default: D5 (Pi GPIO5 / pin 29).",
    )
    parser.add_argument(
        "--program-id",
        type=lambda value: int(value, 0),
        default=0x1234,
        help="RDS program ID as decimal or hex. Default: 0x1234.",
    )
    parser.add_argument(
        "--station",
        help="Optional RDS station text, ASCII only, up to 96 bytes.",
    )
    parser.add_argument(
        "--radio-text",
        help="Optional RDS radio text, ASCII only, up to 106 bytes.",
    )
    return parser


def main() -> int:
    parser = _build_parser()
    args = parser.parse_args()

    if args.power != 0 and not 88 <= args.power <= 115:
        parser.error("--power must be 0 or between 88 and 115")
    if not 0 <= args.program_id <= 0xFFFF:
        parser.error("--program-id must fit in 16 bits")

    station = _ascii_bytes(args.station, "station", 96)
    radio_text = _ascii_bytes(args.radio_text, "radio text", 106)

    try:
        import adafruit_si4713
        import board
        import busio
        import digitalio
    except ImportError as exc:
        print(
            "Missing dependency. On the Pi, install GPIO prerequisites with apt, then create a venv with system packages: sudo apt-get install -y python3-venv i2c-tools libgpiod-dev python3-libgpiod python3-rpi.gpio python3-lgpio && python3 -m venv .venv --system-site-packages && . .venv/bin/activate && pip install adafruit-blinka adafruit-circuitpython-si4713",
            file=sys.stderr,
        )
        print(f"Import failure: {exc}", file=sys.stderr)
        return 1

    try:
        reset_pin = getattr(board, args.reset_pin)
    except AttributeError:
        print(f"Unknown board pin: {args.reset_pin}", file=sys.stderr)
        return 1

    i2c = busio.I2C(board.SCL, board.SDA)
    reset = digitalio.DigitalInOut(reset_pin)

    try:
        radio = adafruit_si4713.SI4713(i2c, reset=reset)
        radio.tx_power = args.power
        radio.tx_frequency_khz = args.freq

        if station is not None or radio_text is not None:
            radio.configure_rds(
                args.program_id,
                station=station,
                rds_buffer=radio_text,
            )

        print(f"SI4713 tuned to {args.freq / 1000:.1f} MHz at power {args.power} dBuV")
        if station is not None:
            print(f"RDS station: {args.station}")
        if radio_text is not None:
            print(f"RDS radio text: {args.radio_text}")
        return 0
    except Exception as exc:  # pragma: no cover - hardware dependent
        print(f"Failed to configure SI4713: {exc}", file=sys.stderr)
        return 1
    finally:
        reset.deinit()
        i2c.deinit()


if __name__ == "__main__":
    raise SystemExit(main())