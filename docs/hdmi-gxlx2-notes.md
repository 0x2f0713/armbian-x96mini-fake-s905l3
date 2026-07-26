# S905L3/GXLX2 HDMI Notes

Earlier HDMI tests left the board unreachable over SSH. The verified working
state is the later `6.18.38-x96gxlx2-gnu15` kernel with matching modules and a
regenerated initrd; see `Verified HDMI Result` below.

## What Failed

The failed test used a driver-only community patch while the DTB still
described the HDMI controller as:

```dts
compatible = "amlogic,meson-gxl-dw-hdmi", "amlogic,meson-gx-dw-hdmi";
reg = <0x0 0xc883a000 0x0 0x1c>;
```

On this S905L3/GXLX2 board, that path reads the HDMI controller ID as
`0d0d:0d:0d` / `baadf00d`, so Meson DRM cannot bind HDMI.

The later serial crash from kernel `6.18.38-x69hdmi` fails even earlier:

```text
pc : dw_hdmi_gx_top_write+0xc4/0xd8
lr : meson_dw_hdmi_bind+0x348/0x58c
x1 : 0000000000008000
```

That is consistent with a direct TOP register write at resource offset
`0x8000` while the active DTB maps the old small HDMI window. The local
GXLX2 patch now checks the HDMI MMIO resource before using direct registers;
if a stale DTB maps less than 64 KiB, HDMI probe fails with:

```text
direct HDMI register layout needs 64 KiB MMIO resource
```

instead of crashing the kernel.

## Better Candidate

A July 2026 upstream RFC for GXLX2/S905L3 reports the matching hardware
model:

- DWC registers are byte-addressed from `0xda800000`.
- TOP registers are 32-bit words at `0xda808000 + index * 4`.
- The display pipeline and HDMI PHY programming stay GXL-like.

The local experimental patch set is:

```text
patches/hdmi/0000-dt-bindings-display-meson-dw-hdmi-add-gxlx2-compatible.patch
patches/hdmi/0001-drm-meson-add-gxlx2-hdmi-support.patch
patches/hdmi/0002-arm64-dts-amlogic-m302a-use-gxlx2-hdmi.patch
```

Install those into Ophub's kernel patch directory for the target kernel
series, rebuild, and test only after rollback access is available. Do not
combine them with the older `0001-meson-gxlx2-hdmi-use-g12a-accessors.patch`
experiment; that patch still depends on the wrong `0xc883a000` resource.

Example local preparation after a clean Ophub checkout:

```sh
sh scripts/prepare-hdmi-patches.sh
```

## Recovery First

If the board is still booting the failed test kernel, mount the boot
partition and restore the previous known-good kernel files:

```sh
cp vmlinuz-6.18.37-ophub zImage
cp uInitrd-6.18.37-ophub uInitrd
sync
```

Power-cycle the board after syncing.

## Safer Test Install

After the board has been recovered and a new HDMI kernel/DTB has been built,
use the guarded installer instead of overwriting `/boot/zImage` by hand:

```sh
sudo scripts/install-hdmi-test-boot.sh \
  --kernel /path/to/test/zImage \
  --initrd /path/to/test/uInitrd \
  --dtb /path/to/test/meson-gxl-s905l3b-m302a.dtb \
  --rollback-delay 300
```

The script backs up `/boot/zImage`, `/boot/uInitrd`, `/boot/uEnv.txt`, and the
active DTB, installs the test files, and arms a systemd rollback service. If
the board reaches userspace and the test boot is acceptable, confirm it before
the delay expires:

```sh
sudo /usr/local/sbin/s905l3-hdmi-test --confirm
```

If the test is bad but SSH still works, roll back immediately:

```sh
sudo /usr/local/sbin/s905l3-hdmi-test --rollback
```

This cannot recover a kernel that panics before userspace starts. For that
case, use the manual boot-partition recovery above.

## Local Validation

On a clean temporary worktree of the Ophub `linux-6.18.y` kernel source, the
local HDMI patches can be validated with:

```sh
sh scripts/validate-hdmi-patches.sh
```

The object and DTB build completed successfully. HDMI video output was later
verified on the physical board with `6.18.38-x96gxlx2-gnu15`; see
`Verified HDMI Result` below.

The generated DTB has the expected runtime HDMI resource:

```dts
compatible = "amlogic,meson-gxlx2-dw-hdmi";
reg = <0x00 0xda800000 0x00 0x10000>;
```

The node name is still inherited from the upstream GXL DTSI as
`hdmi-tx@c883a000`, so `dtc` warns that the unit address and `reg` do not
match. The driver uses `reg`, not the node name.

## Build A Test Bundle

After validation, build a guarded test bundle containing `zImage`, the patched
M302A DTB, config, `System.map`, matching modules, checksums, and the
installers:

```sh
scripts/build-hdmi-test-artifact.sh
```

The script temporarily applies the HDMI patches to the local Ophub kernel tree,
builds `Image`, `meson-gxl-s905l3b-m302a.dtb`, and the module tree, packages
the artifact under `artifacts/hdmi-gxlx2/`, then restores the tracked kernel
source files.

Build-speed notes:

- `JOBS` controls kernel make parallelism. By default the builder uses
  `2 * nproc`; on the current 8-core / 16 GiB host that is 16 jobs. Use
  `JOBS=8 scripts/build-hdmi-test-artifact.sh` if the host is busy.
- `USE_CCACHE` defaults to `auto`. When `ccache` is installed, the builder
  keeps a persistent compiler cache under `.cache/ccache` and creates wrapper
  links under `.cache/ccache-wrappers`. This also works when the downloaded Arm
  GNU toolchain is selected through an absolute `CROSS_COMPILE` prefix.
- Use `USE_CCACHE=false scripts/build-hdmi-test-artifact.sh` to bypass the
  cache, or set `CCACHE_DIR=/path/to/cache` to share cache storage with another
  checkout.
- `BUILD_MODULES` defaults to `true` for real HDMI bundles. Keep it enabled
  when changing `LOCALVERSION`; the board can reset at `/init` if `/uInitrd`
  and `/lib/modules/<release>` do not match the kernel image.
- The builder checks only the four HDMI patch-target files instead of running a
  full `git status` over the 90k-file kernel tree.
- `CONFIG_LOCALVERSION_AUTO` is disabled for the artifact to avoid extra Git
  work during release-string generation.

Latest locally built guarded bundle:

```text
artifacts/hdmi-gxlx2/6.18.38-x96gxlx2-20260725T164750Z.tar.gz
```

## Boot-Loop Result

The `6.18.38-x96gxlx2-20260725T164750Z` artifact was copied to the FAT
boot partition and did boot as `6.18.38-x96gxlx2`, but the board reset around
2.25 seconds after:

```text
platform-mhu c883c404.mailbox: Platform MHU Mailbox registered
hw perfevents: enabled with armv8_cortex_a53 PMU driver
[BL31]: tee size: 0
```

No Linux Oops was printed, and the reset happened before the later Meson DRM
bind point that crashed the older `6.18.38-x69hdmi` image. That failed x96
artifact was built with Ubuntu `aarch64-linux-gnu-gcc 11.4`, unlike the Ophub
kernel images built with Arm GNU `aarch64-none-linux-gnu-gcc`.

The next diagnostic artifact should therefore keep the same GXLX2 HDMI patch
set but rebuild with the local Arm GNU toolchain. The build scripts now prefer
the downloaded toolchain under:

```text
downloads/toolchains/extracted/arm-gnu-toolchain-15.2.rel1-aarch64-aarch64-none-linux-gnu/
```

Use a distinct local version so the serial log proves which kernel booted:

```sh
LOCALVERSION=-x96gxlx2-gnu15 scripts/build-hdmi-test-artifact.sh
```

Latest Arm GNU rebuild:

```text
artifacts/hdmi-gxlx2/6.18.38-x96gxlx2-gnu15-20260725T174758Z.tar.gz
```

This artifact was installed to the FAT boot partition through an offline
OS-disk mount after backing up the restored `6.18.37-ophub` boot state to:

```text
/x96-boot-backups/20260725T174940Z-pre-x96gxlx2-gnu15
```

For this test to be valid, the serial log must start with:

```text
Linux version 6.18.38-x96gxlx2-gnu15
```

## Matching Initrd/Modules Test

The `6.18.38-x96gxlx2-gnu15` serial log later showed that the HDMI path bound
successfully:

```text
meson-dw-hdmi da800000.hdmi-tx: Detected HDMI TX controller v2.01a with HDCP
meson-drm d0100000.vpu: bound da800000.hdmi-tx
[drm] Initialized meson 1.0.0
meson-drm d0100000.vpu: [drm] fb0: mesondrmfb frame buffer device
```

The board then reset at the userspace handoff:

```text
Run /init as init process
GXLX2:BL1...
```

At that point `/uInitrd` was still for `6.18.37-ophub` and the rootfs did not
have `/lib/modules/6.18.38-x96gxlx2-gnu15`. The current offline test state
keeps the same HDMI kernel and DTB, installs the matching module tree, and
regenerates:

```text
/boot/uInitrd
/boot/initrd.img-6.18.38-x96gxlx2-gnu15
/lib/modules/6.18.38-x96gxlx2-gnu15
```

The prepared boot partition still uses:

```text
LINUX=/zImage
INITRD=/uInitrd
FDT=/dtb/amlogic/meson-gxl-s905l3b-m302a.dtb
```

For a fresh offline OS-disk mount, use the bundle's installer from an ARM64
Linux host:

```sh
sudo ./install-hdmi-test-os-disk.sh \
  --root-dir /mnt/x96root-rw \
  --boot-dir /mnt/x96boot-rw \
  --modules-tar ./modules-6.18.38-x96gxlx2-gnu15.tar.gz \
  --kernel ./zImage \
  --dtb ./meson-gxl-s905l3b-m302a.dtb
```

The script stores boot-file backups under the mounted rootfs instead of the
small FAT boot partition, extracts matching modules, runs `depmod` and
`update-initramfs` in the chroot, then rewrites `/uInitrd` from the generated
`initrd.img`.

Read-only verification of the prepared OS disk showed:

```text
/boot/uInitrd: AArch64 Linux RAMDisk Image, data size 24442324 bytes
/boot/initrd.img-6.18.38-x96gxlx2-gnu15: present
/lib/modules/6.18.38-x96gxlx2-gnu15/modules.dep: present
r8723bs.ko vermagic: 6.18.38-x96gxlx2-gnu15 SMP preempt mod_unload aarch64
```

`lsinitramfs` also shows `usr/lib/modules/6.18.38-x96gxlx2-gnu15` inside the
generated initramfs. There are no persisted rootfs logs newer than the earlier
July 21 boot, so the latest prepared test still needs a serial log or a
successful network boot to determine whether it passes the `/init` handoff.

## Verified HDMI Result

The manual test result confirmed HDMI output works, and runtime SSH checks
confirmed the board reached userspace on the prepared kernel/initrd/module
state:

```text
Linux armbian 6.18.38-x96gxlx2-gnu15 #6 SMP PREEMPT_DYNAMIC Sun Jul 26 00:46:18 +07 2026 aarch64 GNU/Linux
systemctl is-system-running: running
failed systemd units: 0
```

DRM and framebuffer state:

```text
/sys/class/drm/card0-HDMI-A-1/status: connected
/sys/class/drm/card0-HDMI-A-1/enabled: enabled
/sys/class/drm/card0-HDMI-A-1/modes: 1920x1080
/sys/class/graphics/fb0/name: mesondrmfb
fb0 mode: 1920x1080, 32 bpp
```

Kernel log evidence:

```text
meson-dw-hdmi da800000.hdmi-tx: Detected HDMI TX controller v2.01a with HDCP
meson-dw-hdmi da800000.hdmi-tx: registered DesignWare HDMI I2C bus driver
meson-drm d0100000.vpu: bound da800000.hdmi-tx
[drm] forcing HDMI-A-1 connector on
[drm] Initialized meson 1.0.0 for d0100000.vpu on minor 0
meson-drm d0100000.vpu: [drm] fb0: mesondrmfb frame buffer device
```

The matching module/initrd state is also live:

```text
/boot/uInitrd: present
/boot/initrd.img-6.18.38-x96gxlx2-gnu15: present
/lib/modules/6.18.38-x96gxlx2-gnu15: present
r8723bs.ko vermagic: 6.18.38-x96gxlx2-gnu15 SMP preempt mod_unload aarch64
```

Non-HDMI follow-up from the same SSH check: this HDMI test DTB/kernel boot has
no active LED class entries and no Wi-Fi interface from `iw dev`. The earlier
Wi-Fi/LED device-tree work still needs to be merged into the HDMI test state
before this becomes the full board support image.

## Conservative eMMC Result

The first HDMI-good DTB still inherited the parent M302A eMMC timing:

```dts
bus-width = <8>;
cap-mmc-highspeed;
mmc-ddr-1_8v;
mmc-hs200-1_8v;
max-frequency = <200000000>;
```

On this board that failed before creating the eMMC block device:

```text
mmc2: tuning execution failed: -5
mmc2: error -5 whilst initialising MMC card
mmc2: Failed to initialize a non-removable card
```

The local eMMC patch set deliberately drops those inherited high-speed modes,
uses legacy 1-bit timing capped at 400 kHz, and clamps Meson MMC requests
before `mmc_add_host()`:

```dts
&sd_emmc_c {
	status = "okay";
	/delete-property/ cap-mmc-highspeed;
	/delete-property/ mmc-ddr-1_8v;
	/delete-property/ mmc-hs200-1_8v;
	bus-width = <1>;
	amlogic,max-request-blocks = <8>;
	max-frequency = <400000>;
};
```

The verified runtime DTB has:

```dts
mmc@74000 {
	status = "okay";
	bus-width = <0x01>;
	amlogic,max-request-blocks = <0x08>;
	max-frequency = <0x61a80>;
	non-removable;
	disable-wp;
};
```

With that DTB, the board booted the same `6.18.38-x96gxlx2-gnu15` HDMI kernel,
kept rootfs on microSD, and enumerated the internal eMMC:

```text
/dev/mmcblk1p2: rootfs on microSD
/dev/mmcblk1p1: boot partition on microSD
/dev/mmcblk2: internal eMMC on d0074000.mmc
mmcblk2 size: 7818182656 bytes
```

Read-only spot checks succeeded after marking the eMMC block device read-only:

```text
read sector 0: ok
read sector 264: ok
read last sector: ok
```

The earlier DTB-only conservative timing boot was still unreliable for normal
user-space tools until the block queue was limited:

```sh
blockdev --setro /dev/mmcblk2
echo 4 > /sys/block/mmcblk2/queue/max_sectors_kb
echo 2 > /sys/block/mmcblk2/queue/nomerges
echo 0 > /sys/block/mmcblk2/queue/read_ahead_kb
```

After applying those queue limits, the previously failing sectors read cleanly,
`fdisk -l /dev/mmcblk2` completed without I/O errors, and 1 MiB read tests from
both the start and end of the device completed without new MMC errors.

That was not sufficient for a clean boot because early `mmcblk` and userspace
probes could still issue larger reads before the service applied queue limits.
The verified fix adds `patches/hdmi/0003-mmc-meson-gx-allow-limiting-request-blocks.patch`
and sets `amlogic,max-request-blocks = <8>` in the M302A DTB patch. The local
tested artifact was:

```text
artifacts/emmc-maxreq/6.18.38-x96gxlx2-gnu15-20260725T221253Z
zImage sha256: e10ae7273b48197c1b40599b7c6f4fdbe5752a3df290866a201a91ea2647c7b7
dtb sha256: 8d278f3414559b31065686ae8851d85edc191220a12e11b93f9a1392e6542034
```

After installing that `zImage` and DTB, the board booted as:

```text
Linux version 6.18.38-x96gxlx2-gnu15 ... #8 SMP PREEMPT_DYNAMIC Sun Jul 26 05:05:30 +07 2026
```

Runtime eMMC verification showed:

```text
/sys/block/mmcblk2/queue/max_hw_sectors_kb: 4
/sys/block/mmcblk2/queue/max_sectors_kb: 4
/sys/block/mmcblk2/queue/read_ahead_kb: 0
/sys/block/mmcblk2/queue/nomerges: 2
```

Fresh dmesg contained the normal `mmc2` registration lines and no eMMC I/O
errors. `fdisk -l /dev/mmcblk2`, 4 KiB direct reads from the beginning and end
of the device, and a 1 MiB direct read completed without adding new kernel log
lines.

That `#8` boot was eMMC-clean but not HDMI-good: the local kernel `.config`
still had `CONFIG_DRM_MESON` disabled from the earlier no-DRM diagnostic, so
Linux reached userspace but HDMI never bound and the display stayed on the
bootloader image. The build script now explicitly enables Meson DRM/HDMI for
normal artifacts.

The corrected local tested artifact was:

```text
artifacts/hdmi-emmc-fixed/6.18.38-x96gxlx2-gnu15-20260726T015252Z
zImage sha256: 261ff290ba7539efa32075e05ff977dc4890bf39d0abeeba1de92951eb55d692
dtb sha256: 8d278f3414559b31065686ae8851d85edc191220a12e11b93f9a1392e6542034
```

After installing that `zImage` and the same DTB, the board booted as:

```text
Linux version 6.18.38-x96gxlx2-gnu15 ... #9 SMP PREEMPT_DYNAMIC Sun Jul 26 08:47:48 +07 2026
```

Runtime verification showed:

```text
CONFIG_DRM_MESON=y
CONFIG_DRM_MESON_DW_HDMI=y
/sys/class/drm/card0-HDMI-A-1/status: connected
/sys/class/drm/card0-HDMI-A-1/enabled: enabled
/sys/class/graphics/fb0/name: mesondrmfb
/sys/block/mmcblk2/queue/max_hw_sectors_kb: 4
```

An attempted DTB-only fix using the documented Meson
`amlogic,dram-access-quirk` property is not usable on this board. It made the
card enumerate, but `mmcblk` failed to bind:

```text
mmc2: new MMC card at address 0001
mmcblk mmc2:0001: probe with driver mmcblk failed with error -22
```

The board was rolled back to the DTB without that property.

Caveat: `fdisk -l /dev/mmcblk2` reported only disk geometry, not a partition
table. Treat this as verified eMMC enumeration and conservative read access,
not yet a high-speed or mountable eMMC configuration.
