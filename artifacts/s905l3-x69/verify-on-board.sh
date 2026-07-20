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

echo "driver log:"
dmesg | grep -iE '8189|rtl|sdio|cfg80211|wlan|led' | tail -160 || true
