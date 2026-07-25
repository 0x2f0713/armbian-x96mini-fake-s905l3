#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PATCH_DIR="${PATCH_DIR:-${ROOT}/ophub-amlogic-s9xxx-armbian/compile-kernel/tools/patch/linux-6.18.y}"

install -d "${PATCH_DIR}"

for patch in "${PATCH_DIR}"/*gxlx2*use-g12a-accessors*.patch; do
	[ -e "${patch}" ] || continue
	mv "${patch}" "${patch}.disabled"
done

for patch in "${ROOT}"/patches/hdmi/*.patch; do
	cp "${patch}" "${PATCH_DIR}/"
done

find "${PATCH_DIR}" -maxdepth 1 -type f -printf '%f\n' | sort
