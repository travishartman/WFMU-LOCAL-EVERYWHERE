#!/bin/sh
# Usage: ./broadcast_fm.sh <freq_mhz>
# Pick freq by scanning your local FM dial for a quiet/unused frequency first.
# Prefer mid-band (~95-100MHz) over the edges (88 or 106-108MHz) -- harmonic
# distortion from this software approach is documented to be worse at the edges.
freq="${1:?usage: broadcast_fm.sh <freq_mhz>}"
sox -t mp3 http://localhost:8000/wfmu.mp3 -t wav -r 44100 -c 2 - | \
  sudo ~/PiFmAdv/src/pi_fm_adv --freq "$freq" --audio -
