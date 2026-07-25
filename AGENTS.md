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

The verified eMMC state is the HDMI-good `6.18.38-x96gxlx2-gnu15` kernel with
the Meson MMC host request clamp and matching DTB property. Runtime
verification showed:

- Kernel release: `6.18.38-x96gxlx2-gnu15`
- Kernel build line: `#8 SMP PREEMPT_DYNAMIC Sun Jul 26 05:05:30 +07 2026`
- Rootfs: `/dev/mmcblk1p2`
- Boot partition: `/dev/mmcblk1p1`
- eMMC host: `d0074000.mmc`
- eMMC block device: `/dev/mmcblk2`
- eMMC size: `7818182656` bytes
- eMMC mode in runtime DTB: 1-bit bus, `max-frequency = <400000>`,
  `amlogic,max-request-blocks = <8>`
- Kernel hardware queue clamp: `max_hw_sectors_kb=4`
- Runtime safety queue settings: `max_sectors_kb=4`, `nomerges=2`,
  `read_ahead_kb=0`, default read-only

Keep eMMC checks read-only by default. Without the kernel-side request clamp,
early `mmcblk` and userspace reads can report `Input/output error` before the
systemd queue-limit service has a chance to run. With the clamp active,
fresh-boot dmesg had no eMMC I/O errors, `fdisk -l /dev/mmcblk2` succeeded,
4 KiB direct reads from the start and end of the device succeeded, and a 1 MiB
direct read completed without adding new kernel log lines.

Do not add `amlogic,dram-access-quirk` to this GXL eMMC node. That DTB-only
test made the card enumerate but caused `mmcblk` probe to fail with `error
-22`, so `/dev/mmcblk2` was not created.

## Build Notes

Use `scripts/build-hdmi-test-artifact.sh` for the HDMI/eMMC kernel and DTB
bundle. The script defaults to `JOBS=2*nproc`, uses the local Arm GNU
toolchain when present, and enables `ccache` automatically through
`.cache/ccache` and `.cache/ccache-wrappers`. Keep that cache directory
between builds.

When changing only built-in code or DTB while keeping the same
`LOCALVERSION`, `BUILD_MODULES=false` is acceptable for a fast boot-file-only
test. If `LOCALVERSION` changes, build and install the matching module tree and
regenerate `uInitrd`.

The FAT `/boot` partition is small. Before guarded installs, check free space;
old test backups can be moved to the root filesystem. During the verified eMMC
test, previous `/boot/*backup*` directories were moved under `/root`, then the
guarded installer created `/boot/hdmi-test-backups/20260725T221523Z`.
