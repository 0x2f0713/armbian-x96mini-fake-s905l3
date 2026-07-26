#!/bin/sh
set -eu

DEV="${DEV:-/dev/mmcblk2}"
BS="${BS:-4K}"
COUNT="${COUNT:-256}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-120}"

die() {
	echo "error: $*" >&2
	exit 1
}

[ -b "${DEV}" ] || die "block device not found: ${DEV}"

echo "kernel=$(uname -r)"
echo "device=${DEV}"
echo "system_state=$(systemctl is-system-running --wait 2>/dev/null || true)"

echo "ios:"
for ios in /sys/kernel/debug/mmc*/ios; do
	[ -e "${ios}" ] || continue
	echo "-- ${ios}"
	cat "${ios}" || true
done

block="$(basename "${DEV}")"
queue="/sys/block/${block}/queue"

echo "queue:"
for f in max_hw_sectors_kb max_sectors_kb nomerges read_ahead_kb scheduler; do
	[ -e "${queue}/${f}" ] || continue
	printf '%s=' "${f}"
	cat "${queue}/${f}" || true
done
if [ -e "/sys/block/${block}/ro" ]; then
	printf 'ro='
	cat "/sys/block/${block}/ro" || true
fi
if [ -e "/sys/block/${block}/size" ]; then
	printf 'size512='
	cat "/sys/block/${block}/size" || true
fi

blockdev --setro "${DEV}" 2>/dev/null || true

echo "read_test:"
if command -v timeout >/dev/null 2>&1; then
	timeout "${TIMEOUT_SECONDS}" dd if="${DEV}" of=/dev/null bs="${BS}" count="${COUNT}" iflag=direct
else
	dd if="${DEV}" of=/dev/null bs="${BS}" count="${COUNT}" iflag=direct
fi

if command -v fdisk >/dev/null 2>&1; then
	fdisk -l "${DEV}" >/dev/null && echo "fdisk_probe=ok" || echo "fdisk_probe=failed"
fi

echo "recent_mmc_log:"
dmesg -T | grep -Ei 'mmc2|mmcblk2|I/O error|error -|timeout|crc' | tail -120 || true
