#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DRIVER_DIR="${ROOT}/src/rtl8189ES_linux"
OUT_DIR="${ROOT}/artifacts/s905l3-x69"
KVER="${KVER:-$(uname -r)}"
KSRC="${KSRC:-/lib/modules/${KVER}/build}"

if [ ! -d "${KSRC}" ]; then
	echo "Kernel headers not found: ${KSRC}" >&2
	exit 1
fi

make -C "${DRIVER_DIR}" ARCH=arm64 KSRC="${KSRC}" KVER="${KVER}" clean
make -C "${DRIVER_DIR}" ARCH=arm64 KSRC="${KSRC}" KVER="${KVER}" -j1

install -d "${OUT_DIR}"
install -m 0644 "${DRIVER_DIR}/8189es.ko" "${OUT_DIR}/8189es.ko"
modinfo "${OUT_DIR}/8189es.ko" | sed -n '1,20p'
