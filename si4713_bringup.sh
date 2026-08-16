#!/usr/bin/env bash
# Bring the SI4713 transmitter up after a boot/reboot.
#
# Do NOT run `pinctrl set 5 op dh` before this — the adafruit library drives the
# RST line (GPIO5) itself during init, and a manual pinctrl override conflicts
# with it and causes "Timeout waiting for SI4713 to respond".
#
# An empty `i2cdetect` grid before this runs is NORMAL: the chip sits in reset
# until the library pulses RST. This script lets the library do that, with one
# retry in case the first power-up races the reset pulse.
#
# Usage:
#   ./si4713_bringup.sh [FREQ_MHZ] [STATION] [RADIO_TEXT]
# Examples:
#   ./si4713_bringup.sh
#   ./si4713_bringup.sh 96.0 WFMU "WFMU live"

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$HERE/.venv/bin/python"
CONTROL="$HERE/si4713_control.py"

FREQ="${1:-96.0}"
STATION="${2:-WFMU}"
RADIO_TEXT="${3:-WFMU live}"

if [ ! -x "$PY" ]; then
  echo "Error: venv python not found at $PY — run ./setup_si4713_env.sh first." >&2
  exit 1
fi

run_control() {
  "$PY" "$CONTROL" "$FREQ" --station "$STATION" --radio-text "$RADIO_TEXT"
}

echo "Bringing up SI4713 at ${FREQ} MHz (station=${STATION})..."
if run_control; then
  echo "SI4713 bring-up succeeded."
  exit 0
fi

echo "First attempt failed (likely a reset-pulse race). Retrying once..." >&2
sleep 2
if run_control; then
  echo "SI4713 bring-up succeeded on retry."
  exit 0
fi

cat >&2 <<'EOF'

SI4713 bring-up failed twice. This is almost always a physical connection:
  - Reseat RST (Pi pin 29 / GPIO5), Vin (pin 1), and GND (pin 6) — power OFF first.
  - Do NOT run `pinctrl set 5 op dh` before this script (it conflicts with the
    library's own reset pulse). Use pinctrl only to confirm wiring via i2cdetect.
  - To diagnose wiring only: `pinctrl set 5 op dh && i2cdetect -y 1` (expect 63),
    then reboot and run this script again with no pinctrl.
EOF
exit 1
