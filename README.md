# S905L3 X69 Mini Armbian Wi-Fi and LED Fix

This repository contains the files used to make Wi-Fi and the front LEDs work on an S905L3/X69 Mini style board running Ophub Armbian with kernel `6.18.37-ophub`.

The board was identified from the Android firmware `s_22-02-24-17_X69_MINI_S905W_800-M96-EMCP-REV1.ZIP`. The Wi-Fi device is Realtek RTL8189ES on SDIO:

```text
SDIO_ID=024C:8179
MODALIAS=sdio:c07v024Cd8179
```

The LED GPIOs were taken from the Android DTB:

```text
sys LED: GPIODV_24, active high
net LED: GPIOAO_9, active high
```

## What Is Included

- `artifacts/s905l3-x69/8189es.ko` - prebuilt RTL8189ES module for `6.18.37-ophub`.
- `artifacts/s905l3-x69/meson-gxl-s905l3b-m302a.dtb` - DTB with `gpio-leds` nodes for this board.
- `artifacts/s905l3-x69/install-on-board.sh` - installs the module, autoload config, module options, and DTB.
- `artifacts/s905l3-x69/verify-on-board.sh` - checks module binding, Wi-Fi visibility, scans, and LED sysfs controls.
- `src/rtl8189ES_linux/` - patched RTL8189ES source based on `https://github.com/jwrdegoede/rtl8189ES_linux` commit `2d9a8af`.
- `third_party/rtl8189ES_linux` - submodule pinned to the upstream driver commit used as the patch base.
- `patches/rtl8189es-linux-6.18-cfg80211.patch` - the Linux 6.18 cfg80211 API patch.
- `patches/meson-gxl-s905l3b-m302a-x69-leds.dts` - DTS source for the patched LED DTB.

## Install On A Fresh Armbian Instance

Use this path when the fresh install is already running kernel `6.18.37-ophub` and uses:

```text
FDT=/dtb/amlogic/meson-gxl-s905l3b-m302a.dtb
```

Copy `artifacts/s905l3-x69.tar.gz` to the board, then run:

```sh
mkdir -p /tmp/s905l3-x69
tar -xzf /tmp/s905l3-x69.tar.gz -C /tmp/s905l3-x69 --strip-components=1
cd /tmp/s905l3-x69
sh ./install-on-board.sh
reboot
```

After reboot:

```sh
cd /tmp/s905l3-x69
sh ./verify-on-board.sh
```

The installer backs up the existing DTB as:

```text
/boot/dtb/amlogic/meson-gxl-s905l3b-m302a.dtb.bak-YYYYMMDDHHMMSS
```

## Rebuild The Wi-Fi Module On The Board

Install kernel headers and build tools on the board first. Then run from this repo:

```sh
sh scripts/build-8189es-on-board.sh
```

The build script uses `-j1` because this class of board can run out of memory during a parallel driver build.

The current module is built with Realtek concurrent mode enabled, so the driver exposes `wlan0` and `wlan1` from the same physical RTL8189ES chip. For a single interface build, edit `src/rtl8189ES_linux/Makefile`:

```make
CONFIG_CONCURRENT_MODE = n
```

Then rebuild and reinstall.

## Upstream Driver Submodule

The checked-in `src/rtl8189ES_linux/` tree is the build source used by the scripts. The submodule is included for provenance and refresh work:

```sh
git submodule update --init third_party/rtl8189ES_linux
```

It should resolve to:

```text
2d9a8afb5d12de1cfc4ab5ad3d1a61e1937629bd
```

The patch in `patches/rtl8189es-linux-6.18-cfg80211.patch` is the difference between that upstream commit and the vendored `src/rtl8189ES_linux/` tree.

## Rebuild The LED DTB

From a system with `dtc` installed:

```sh
sh scripts/build-led-dtb.sh
```

This writes:

```text
artifacts/s905l3-x69/meson-gxl-s905l3b-m302a.dtb
```

## Verified Result

The installed board was verified after reboot:

```text
kernel=6.18.37-ophub
module=8189es
sdio_driver=rtl8189es
sdio_id=024C:8179
nm_wifi_radio=enabled
wlan0:wifi:disconnected
wlan1:wifi:disconnected
scan_bssid_count=45
x69:blue:net
x69:blue:sys
sys_led_write=0->1
net_led_write=1->0
```
