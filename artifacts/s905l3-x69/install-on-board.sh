#!/bin/sh
set -eu

KVER="$(uname -r)"
DTB_PATH="/boot/dtb/amlogic/meson-gxl-s905l3b-m302a.dtb"
MODULE_DIR="/lib/modules/${KVER}/kernel/drivers/net/wireless/realtek"

echo "kernel=${KVER}"

if [ ! -f ./8189es.ko ]; then
	echo "8189es.ko must be in the current directory" >&2
	exit 1
fi

if [ ! -f ./meson-gxl-s905l3b-m302a.dtb ]; then
	echo "meson-gxl-s905l3b-m302a.dtb must be in the current directory" >&2
	exit 1
fi

MODULE_VERMAGIC="$(modinfo -F vermagic ./8189es.ko | awk '{print $1}')"
if [ "${MODULE_VERMAGIC}" != "${KVER}" ]; then
	echo "8189es.ko vermagic ${MODULE_VERMAGIC} does not match running kernel ${KVER}" >&2
	exit 1
fi

install -d "${MODULE_DIR}"
install -m 0644 ./8189es.ko "${MODULE_DIR}/8189es.ko"
depmod -a "${KVER}"
printf '%s\n' 8189es > /etc/modules-load.d/8189es.conf
printf '%s\n' 'options 8189es rtw_load_phy_file=0' > /etc/modprobe.d/8189es.conf

if [ -f "${DTB_PATH}" ]; then
	cp -a "${DTB_PATH}" "${DTB_PATH}.bak-$(date +%Y%m%d%H%M%S)"
fi
install -m 0644 ./meson-gxl-s905l3b-m302a.dtb "${DTB_PATH}"
sync

if lsmod | grep -q '^8189es '; then
	modprobe -r 8189es || true
fi

if ! modprobe 8189es; then
	echo "modprobe 8189es failed; recent kernel log follows" >&2
	dmesg | grep -iE '8189|rtl|sdio|cfg80211|firmware' | tail -80 >&2 || true
	exit 1
fi

echo "modules:"
lsmod | grep -E '8189|cfg80211' || true

echo "sdio:"
for uevent in /sys/bus/sdio/devices/*/uevent; do
	[ -e "${uevent}" ] || continue
	echo "${uevent}"
	cat "${uevent}"
done

echo "links:"
ip link show

echo "wireless:"
iw dev || true
nmcli dev status || true

echo "driver log:"
dmesg | grep -iE '8189|rtl|sdio|cfg80211|wlan' | tail -120 || true

echo "leds require reboot for the updated DTB:"
ls -la /sys/class/leds || true
