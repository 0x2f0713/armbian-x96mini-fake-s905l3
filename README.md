# S905L3 X96 Mini Armbian Wi-Fi, LED, and eMMC Fix

This repository contains the files used to make Wi-Fi, the front LEDs, HDMI,
and internal eMMC detection work on an S905L3/X96 Mini style board running
Ophub Armbian. The original Wi-Fi/LED artifact targets kernel
`6.18.37-ophub`; the newer HDMI/eMMC patch set targets
`6.18.38-x96gxlx2-gnu15`.

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

The internal eMMC is wired to the `sd_emmc_c` controller at `d0074000.mmc`.
Wide-bus and high-speed modes failed on this board, so the HDMI/eMMC kernel
DTB uses a conservative legacy fallback profile:

```text
bus-width = 1
max-frequency = 20000000
legacy timing only
```

## What Is Included

- `artifacts/s905l3-x96/8189es.ko` - prebuilt RTL8189ES module for `6.18.37-ophub`.
- `artifacts/s905l3-x96/meson-gxl-s905l3b-m302a.dtb` - DTB with `gpio-leds` nodes and conservative eMMC timing for this board.
- `artifacts/s905l3-x96/install-on-board.sh` - installs the module, autoload config, module options, and DTB.
- `artifacts/s905l3-x96/install-emmc-queue-limits.sh` - installs boot-time queue limits for reliable read-only eMMC access.
- `artifacts/s905l3-x96/verify-on-board.sh` - checks module binding, Wi-Fi visibility, scans, LED sysfs controls, and eMMC detection.
- `src/rtl8189ES_linux/` - patched RTL8189ES source based on `https://github.com/jwrdegoede/rtl8189ES_linux` commit `2d9a8af`.
- `third_party/rtl8189ES_linux` - submodule pinned to the upstream driver commit used as the patch base.
- `patches/rtl8189es-linux-6.18-cfg80211.patch` - the Linux 6.18 cfg80211 API patch.
- `patches/meson-gxl-s905l3b-m302a-x96-leds.dts` - DTS source for the patched LED DTB.
- `patches/hdmi/` - HDMI/eMMC kernel patch stack for `6.18.38-x96gxlx2-gnu15`, including the X96 LED DTB patch.
- `scripts/build-hdmi-test-artifact.sh` - builds the HDMI/eMMC DTB/kernel bundle and the matching RTL8189ES module.
- `scripts/install-8189es-module.sh` - installs only the RTL8189ES module for the running kernel and leaves the DTB untouched.
- `scripts/build-emmc-speed-test-dtbs.sh` - builds DTB-only eMMC frequency sweep artifacts from the HDMI patch stack.
- `scripts/benchmark-emmc-read.sh` - captures eMMC mode, queue settings, direct-read speed, and recent MMC logs on the board.

## Install On A Fresh Armbian Instance

Use this path when the fresh install is already running kernel `6.18.37-ophub` and uses:

```text
FDT=/dtb/amlogic/meson-gxl-s905l3b-m302a.dtb
```

Copy `artifacts/s905l3-x96.tar.gz` to the board, then run:

```sh
mkdir -p /tmp/s905l3-x96
tar -xzf /tmp/s905l3-x96.tar.gz -C /tmp/s905l3-x96 --strip-components=1
cd /tmp/s905l3-x96
sh ./install-on-board.sh
reboot
```

After reboot:

```sh
cd /tmp/s905l3-x96
sh ./verify-on-board.sh
```

The installer backs up the existing DTB as:

```text
/boot/dtb/amlogic/meson-gxl-s905l3b-m302a.dtb.bak-YYYYMMDDHHMMSS
```

## HDMI/eMMC Kernel Path

Use this path for the newer `6.18.38-x96gxlx2-gnu15` HDMI/eMMC kernel. Build
from the host:

```sh
scripts/build-hdmi-test-artifact.sh
```

For a fast rebuild when the kernel release is unchanged and only the DTB or
external Wi-Fi module changed:

```sh
LOCALVERSION=-x96gxlx2-gnu15 BUILD_MODULES=false BUILD_WIFI=true scripts/build-hdmi-test-artifact.sh
```

The generated bundle contains `zImage`, `meson-gxl-s905l3b-m302a.dtb`,
`8189es.ko`, and `install-8189es-module.sh`. Install the boot files with the
guarded HDMI installer, then install Wi-Fi with:

```sh
sh ./install-8189es-module.sh ./8189es.ko
```

Do not use `artifacts/s905l3-x96/install-on-board.sh` on the HDMI/eMMC kernel
state; that older all-in-one installer also replaces the DTB with the
`6.18.37-ophub` LED DTB.

## Rebuild The Wi-Fi Module On The Board

Install kernel headers and build tools on the board first. Then run from this repo:

```sh
sh scripts/build-8189es-on-board.sh
```

The build script uses `-j1` because this class of board can run out of memory during a parallel driver build.

The current module is built with Realtek concurrent mode disabled, so the
driver exposes only `wlan0` from the physical RTL8189ES chip. Keep this
default for stability:

```make
CONFIG_CONCURRENT_MODE ?= n
```

The installer writes conservative module options that disable external PHY
loading and Realtek IPS/LPS power saving:

```text
rtw_load_phy_file=0 rtw_ips_mode=0 rtw_power_mgnt=0 rtw_lps_level=0 rtw_drv_log_level=2
```

Rebuild and reinstall after changing either the kernel release or this driver
source.

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

## Rebuild The DTB

From a system with `dtc` installed:

```sh
sh scripts/build-led-dtb.sh
```

This writes:

```text
artifacts/s905l3-x96/meson-gxl-s905l3b-m302a.dtb
```

## eMMC Notes

The original mainline-style eMMC settings reached `mmc2` but failed during
tuning or card setup. The verified fallback disables high-speed, DDR, and HS200
modes and keeps the controller in 1-bit legacy timing. The first safe fallback
used 400 kHz and read at about 49 kB/s. A later frequency sweep verified 20 MHz
legacy timing at about 2.2 MB/s. A 25 MHz DTB booted Linux from microSD but the
internal eMMC failed to initialize with `mmc2: error -84`, so 20 MHz is the
current safe cap.

The eMMC also needs small requests on this board. Without this, early block
probing and normal user-space probes may merge reads and report
`Input/output error` even though small direct sector reads work.

For the `6.18.38-x96gxlx2-gnu15` HDMI/eMMC image, the verified fix is a
kernel-side Meson MMC host clamp plus a DTB property:

```text
amlogic,max-request-blocks = <8>
```

That makes the registered block queue expose:

```text
max_hw_sectors_kb = 4
```

from the moment `/dev/mmcblk2` is created, before `mmcblk` and userspace can
issue larger reads. The runtime safety service still applies:

```text
max_sectors_kb = 4
nomerges = 2
read_ahead_kb = 0
read-only block device
```

After installation, the eMMC should appear under the `d0074000.mmc` host, for example:

```text
/dev/mmcblk2
/dev/mmcblk2boot0
/dev/mmcblk2boot1
```

The main eMMC device may not contain a usable partition table. Partitioning or formatting it is a separate destructive step and is not done by the installer.

The older `6.18.37-ophub` Wi-Fi/LED artifact does not include the kernel-side
MMC host clamp, so it relies on the queue-limit service after userspace starts.

The latest verified `6.18.38-x96gxlx2-gnu15` boot had no eMMC I/O errors in
fresh dmesg, reported `max_hw_sectors_kb=4`, and passed `fdisk -l
/dev/mmcblk2`, 4 KiB direct reads from the beginning and end of the device,
and a 1 MiB direct read without adding new kernel log lines.

## Verified HDMI/eMMC/Wi-Fi/LED Result

The current `6.18.38-x96gxlx2-gnu15` board state was verified after the
single-interface RTL8189ES reboot:

```text
kernel=6.18.38-x96gxlx2-gnu15
system_state=running
hdmi_status=connected
hdmi_enabled=enabled
framebuffer=mesondrmfb
module=8189es
module_vermagic=6.18.38-x96gxlx2-gnu15
module_srcversion=3590E40F0EF4B5E37F1FDDD
module_sha256=8fd51a045cf71d75c6392732870400d41dba079bcacd76768adb4b281adee6eb
sdio_driver=rtl8189es
sdio_id=024C:8179
wlan_interfaces=wlan0
wifi_link=connected
nm_wifi_p2p_placeholder=p2p-dev-wlan0 disconnected
wifi_dmesg_wlan1=0
wifi_dmesg_buddy_intf=0
wifi_dmesg_ips_pwr_down=0
wifi_dmesg_cfg80211_ch_switch_notify=0
wifi_dmesg_warning=0
x96:blue:net
x96:blue:sys
sys_led_write=0->1
net_led_write=1->0
emmc_block=mmcblk2
emmc_read_only=1
emmc_max_hw_sectors_kb=4
emmc_max_sectors_kb=4
emmc_nomerges=2
emmc_read_ahead_kb=0
emmc_read_4k=ok
```

The verified LED DTB adds:

```dts
leds {
	compatible = "gpio-leds";

	led-sys {
		label = "x96:blue:sys";
		gpios = <&gpio GPIODV_24 GPIO_ACTIVE_HIGH>;
		default-state = "on";
		linux,default-trigger = "heartbeat";
	};

	led-net {
		label = "x96:blue:net";
		gpios = <&gpio_ao GPIOAO_9 GPIO_ACTIVE_HIGH>;
		default-state = "off";
	};
};
```

## Legacy Verified Result

The original `6.18.37-ophub` Wi-Fi/LED artifact was verified after reboot:

```text
kernel=6.18.37-ophub
module=8189es
sdio_driver=rtl8189es
sdio_id=024C:8179
nm_wifi_radio=enabled
wlan0:wifi:disconnected
wlan1:wifi:disconnected
scan_bssid_count=45
x96:blue:net
x96:blue:sys
sys_led_write=0->1
net_led_write=1->0
emmc_detected=yes
emmc_block=mmcblk2
emmc_size=7.28 GiB
emmc_read_only=1
emmc_max_sectors_kb=4
emmc_nomerges=2
emmc_read_ahead_kb=0
emmc_read_sector0=ok
emmc_read_last_sector=ok
```
