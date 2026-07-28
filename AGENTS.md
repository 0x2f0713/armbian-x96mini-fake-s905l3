# Agent Notes

## HDMI Verified State

The manual boot result was provided: HDMI output works on the prepared test
state. Runtime SSH verification showed:

- Kernel release: `6.18.38-x96gxlx2-gnu15`
- DRM connector: `card0-HDMI-A-1`
- Connector state: `connected`, `enabled`
- Framebuffer: `mesondrmfb`
- Mode: `1920x1080`
- System state: `running`, with no failed systemd units

The working HDMI boot state is:

- Kernel release: `6.18.38-x96gxlx2-gnu15`
- Boot files: `/boot/zImage`, `/boot/uInitrd`,
  `/boot/initrd.img-6.18.38-x96gxlx2-gnu15`
- DTB: `/boot/dtb/amlogic/meson-gxl-s905l3b-m302a.dtb`
- Modules: `/lib/modules/6.18.38-x96gxlx2-gnu15`

Do not replace this HDMI test state without first preserving a rollback path.
Any next bring-up work should treat the SSH runtime data and the user's manual
HDMI confirmation as authoritative.

## eMMC Verified State

The verified combined HDMI/eMMC state is `6.18.38-x96gxlx2-gnu15` kernel
build `#9` with Meson DRM enabled, the Meson MMC host request clamp, and the
matching DTB property. Runtime verification showed:

- Kernel release: `6.18.38-x96gxlx2-gnu15`
- Kernel build line: `#9 SMP PREEMPT_DYNAMIC Sun Jul 26 08:47:48 +07 2026`
- Rootfs: `/dev/mmcblk1p2`
- Boot partition: `/dev/mmcblk1p1`
- eMMC host: `d0074000.mmc`
- eMMC block device: `/dev/mmcblk2`
- eMMC size: `7818182656` bytes
- eMMC mode in runtime DTB: 1-bit bus, `max-frequency = <20000000>`,
  `amlogic,max-request-blocks = <8>`
- eMMC clock: `20000000 Hz`, legacy timing
- Kernel hardware queue clamp: `max_hw_sectors_kb=4`
- Runtime safety queue settings: `max_sectors_kb=4`, `nomerges=2`,
  `read_ahead_kb=0`, default read-only
- eMMC read benchmark: 1 MiB direct read at about `2.2 MB/s`
- HDMI: `/sys/class/drm/card0-HDMI-A-1/status=connected`,
  `enabled=enabled`, framebuffer `mesondrmfb`

Keep eMMC checks read-only by default. Without the kernel-side request clamp,
early `mmcblk` and userspace reads can report `Input/output error` before the
systemd queue-limit service has a chance to run. With the clamp active,
fresh-boot dmesg had no eMMC I/O errors, `fdisk -l /dev/mmcblk2` succeeded,
4 KiB direct reads from the start and end of the device succeeded, and a 1 MiB
direct read completed without adding new kernel log lines.

The original 400 kHz fallback read at about `49 kB/s`; 20 MHz legacy timing is
the verified fast profile. A 25 MHz DTB reached Linux from microSD but failed
to initialize internal eMMC with `mmc2: error -84`, leaving no `/dev/mmcblk2`.
Do not use 25 MHz as the default.

Do not add `amlogic,dram-access-quirk` to this GXL eMMC node. That DTB-only
test made the card enumerate but caused `mmcblk` probe to fail with `error
-22`, so `/dev/mmcblk2` was not created.

## Wi-Fi And LED Verified State

The verified combined HDMI/eMMC/Wi-Fi/LED state is still kernel
`6.18.38-x96gxlx2-gnu15` build `#9`, with the X96 front LED DTB nodes and the
matching external RTL8189ES module installed. Runtime verification after the
single-interface Wi-Fi reboot showed:

- System state: `running`
- LED sysfs entries: `x96:blue:sys`, `x96:blue:net`
- LED GPIO write checks: `sys_led_write=0->1`, `net_led_write=1->0`
- HDMI: `connected`, `enabled`, framebuffer `mesondrmfb`
- Wi-Fi module: `8189es`, vermagic `6.18.38-x96gxlx2-gnu15`,
  srcversion `3590E40F0EF4B5E37F1FDDD`
- Wi-Fi module SHA256:
  `8fd51a045cf71d75c6392732870400d41dba079bcacd76768adb4b281adee6eb`
- Wi-Fi SDIO device: `SDIO_ID=024C:8179`, `DRIVER=rtl8189es`
- Kernel WLAN interface: `wlan0` only, connected
- NetworkManager may still list `p2p-dev-wlan0`; that is a Wi-Fi P2P
  placeholder, not a second kernel `wlan*` netdev
- Fresh-boot dmesg counts: `wlan1=0`, `buddy_intf=0`, `ips_pwr_down=0`,
  `cfg80211_ch_switch_notify=0`, `WARNING:=0`
- eMMC: `/dev/mmcblk2`, read-only, `max_hw_sectors_kb=4`, 4 KiB direct read
  succeeded

The current LED DTB patch is
`patches/hdmi/0005-arm64-dts-amlogic-m302a-add-x96-leds.patch`. It adds
`gpio-leds` entries from the Android DTB: `GPIODV_24` active-high for
`x96:blue:sys` and `GPIOAO_9` active-high for `x96:blue:net`.

Use `scripts/install-8189es-module.sh` for the `6.18.38-x96gxlx2-gnu15`
Wi-Fi module. Do not use the older all-in-one
`artifacts/s905l3-x96/install-on-board.sh` on the HDMI/eMMC test state,
because it also replaces the DTB with the older non-HDMI artifact.

Keep Realtek concurrent mode disabled in `src/rtl8189ES_linux/Makefile`
(`CONFIG_CONCURRENT_MODE ?= n`). Enabling it creates `wlan0` and `wlan1` from
the same RTL8189ES chip and NetworkManager repeatedly scans the unused second
interface. Keep the module options conservative:
`rtw_load_phy_file=0 rtw_ips_mode=0 rtw_power_mgnt=0 rtw_lps_level=0
rtw_drv_log_level=2`.

The local RTL8189ES source also guards `cfg80211_ch_switch_notify()` for STA
mode until `_FW_LINKED` is set. Without that guard, fresh boot can trigger a
kernel WARN from `net/wireless/nl80211.c` during association.

## Build Notes

Use `scripts/build-hdmi-test-artifact.sh` for the HDMI/eMMC kernel and DTB
bundle. The script also builds/packages the external RTL8189ES Wi-Fi module by
default (`BUILD_WIFI=true`) and includes the module-only installer. It defaults
to `JOBS=2*nproc`, uses the local Arm GNU toolchain when present, and enables
`ccache` automatically through `.cache/ccache` and `.cache/ccache-wrappers`.
Keep that cache directory between builds.

Normal builds must keep Meson DRM enabled. A previous boot-only eMMC artifact
(`#8`) was built after a no-DRM diagnostic left `CONFIG_DRM_MESON` disabled in
the reused kernel `.config`; Linux and eMMC worked, but HDMI never bound and
the screen stayed on the bootloader image. The build script now explicitly
enables the Meson DRM/HDMI symbols unless `DISABLE_MESON_DRM=true` is set.

When changing only built-in code or DTB while keeping the same
`LOCALVERSION`, `BUILD_MODULES=false` is acceptable for a fast boot-file-only
test. If `LOCALVERSION` changes, build and install the matching module tree and
regenerate `uInitrd`.

The FAT `/boot` partition is small. Before guarded installs, check free space;
old test backups can be moved to the root filesystem. During the verified eMMC
test, previous `/boot/*backup*` directories were moved under `/root`, then the
guarded installer created `/boot/hdmi-test-backups/20260725T221523Z`.

For eMMC speed tests, use `scripts/build-emmc-speed-test-dtbs.sh` to generate
DTB-only frequency-sweep artifacts and `scripts/benchmark-emmc-read.sh` on the
board. Test in ascending frequency order with the guarded rollback installer.
