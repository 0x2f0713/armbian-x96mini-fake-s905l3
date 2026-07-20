#!/bin/sh
set -u

echo "kernel:"
uname -a

echo "module:"
modinfo 8189es 2>/dev/null | sed -n '1,20p' || true
lsmod | grep -E '8189|cfg80211' || true

echo "sdio:"
for uevent in /sys/bus/sdio/devices/*/uevent; do
	[ -e "${uevent}" ] || continue
	echo "${uevent}"
	cat "${uevent}"
done

echo "network:"
ip -br link
iw dev || true
nmcli dev status || true

echo "leds:"
ls -la /sys/class/leds || true
for led in /sys/class/leds/x69:*; do
	[ -e "${led}" ] || continue
	echo "${led}"
	cat "${led}/max_brightness" "${led}/brightness" || true
	cat "${led}/trigger" || true
done

if [ -d /sys/class/leds/x69:blue:sys ]; then
	echo none > /sys/class/leds/x69:blue:sys/trigger || true
	echo 0 > /sys/class/leds/x69:blue:sys/brightness || true
	sleep 1
	echo 1 > /sys/class/leds/x69:blue:sys/brightness || true
	echo heartbeat > /sys/class/leds/x69:blue:sys/trigger || true
fi

if [ -d /sys/class/leds/x69:blue:net ]; then
	echo 1 > /sys/class/leds/x69:blue:net/brightness || true
	sleep 1
	echo 0 > /sys/class/leds/x69:blue:net/brightness || true
fi

echo "emmc:"
emmc_block=""
for block in /sys/block/mmcblk*; do
	[ -e "${block}" ] || continue
	name="$(basename "${block}")"
	case "${name}" in
		*boot*|*rpmb*) continue ;;
	esac
	path="$(readlink -f "${block}")"
	case "${path}" in
		*/d0074000.mmc/*)
			emmc_block="${name}"
			echo "block=${name}"
			echo "path=${path}"
			size512="$(cat "${block}/size" 2>/dev/null || echo 0)"
			echo "size512=${size512}"
			echo "removable=$(cat "${block}/removable" 2>/dev/null || echo unknown)"
			for info in type name cid csd manfid oemid serial date pre_eol_info life_time; do
				[ -e "${block}/device/${info}" ] || continue
				printf '%s=' "${info}"
				cat "${block}/device/${info}" || true
			done
			if dd if="/dev/${name}" of=/dev/null bs=512 count=1 status=none 2>/tmp/emmc-read.err; then
				echo "read_sector0=ok"
			else
				echo "read_sector0=failed"
				cat /tmp/emmc-read.err
			fi
			if [ "${size512}" -gt 0 ] 2>/dev/null; then
				last_sector=$((size512 - 1))
				if dd if="/dev/${name}" of=/dev/null bs=512 skip="${last_sector}" count=1 status=none 2>/tmp/emmc-read-last.err; then
					echo "read_last_sector=ok"
				else
					echo "read_last_sector=failed"
					cat /tmp/emmc-read-last.err
				fi
			fi
			;;
	esac
done

if [ -z "${emmc_block}" ]; then
	echo "emmc_detected=no"
else
	echo "emmc_detected=yes"
fi

echo "driver log:"
dmesg | grep -iE '8189|rtl|sdio|cfg80211|wlan|led|mmc2|emmc|d0074000|mmcblk2' | tail -220 || true
