#!/bin/sh
set -eu

module_path=${1:-./8189es.ko}
kver=$(uname -r)
module_dir="/lib/modules/${kver}/kernel/drivers/net/wireless/realtek"

die() {
	echo "error: $*" >&2
	exit 1
}

[ "$(id -u)" -eq 0 ] || die "run as root"
[ -f "${module_path}" ] || die "module not found: ${module_path}"
command -v modinfo >/dev/null 2>&1 || die "modinfo is required"
command -v depmod >/dev/null 2>&1 || die "depmod is required"
command -v modprobe >/dev/null 2>&1 || die "modprobe is required"

module_vermagic=$(modinfo -F vermagic "${module_path}" | awk '{print $1}')
[ -n "${module_vermagic}" ] || die "could not read module vermagic"
[ "${module_vermagic}" = "${kver}" ] || die "module vermagic ${module_vermagic} does not match running kernel ${kver}"

install -d "${module_dir}"
install -m 0644 "${module_path}" "${module_dir}/8189es.ko"
depmod -a "${kver}"

printf '%s\n' 8189es >/etc/modules-load.d/8189es.conf
printf '%s\n' 'options 8189es rtw_load_phy_file=0' >/etc/modprobe.d/8189es.conf

if ! lsmod | grep -q '^8189es '; then
	modprobe 8189es
else
	echo "8189es is already loaded; installed module will be used after the next reload or reboot."
fi

echo "kernel=${kver}"
echo "module=$(modinfo -F filename 8189es 2>/dev/null || true)"
echo "vermagic=$(modinfo -F vermagic 8189es 2>/dev/null || true)"

echo "sdio:"
for uevent in /sys/bus/sdio/devices/*/uevent; do
	[ -e "${uevent}" ] || continue
	echo "${uevent}"
	cat "${uevent}"
done

echo "links:"
ip -br link show 2>/dev/null || ip link show || true

echo "wireless:"
if command -v iw >/dev/null 2>&1; then
	iw dev || true
fi
if command -v nmcli >/dev/null 2>&1; then
	nmcli dev status || true
fi

echo "driver log:"
dmesg | grep -iE '8189|rtl|sdio|cfg80211|wlan' | tail -120 || true
