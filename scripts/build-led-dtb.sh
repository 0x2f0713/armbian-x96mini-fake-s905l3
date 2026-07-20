#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SRC="${ROOT}/patches/meson-gxl-s905l3b-m302a-x69-leds.dts"
OUT_DIR="${ROOT}/artifacts/s905l3-x69"
OUT="${OUT_DIR}/meson-gxl-s905l3b-m302a.dtb"

command -v dtc >/dev/null
install -d "${OUT_DIR}"
dtc -I dts -O dtb -o "${OUT}" "${SRC}"
ls -lh "${OUT}"
