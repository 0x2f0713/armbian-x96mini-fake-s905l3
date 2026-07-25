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

The conservative eMMC DTB overlay state booted with HDMI still working and
made the internal eMMC visible while rootfs stayed on the microSD card.
Runtime verification showed:

- Kernel release: `6.18.38-x96gxlx2-gnu15`
- Rootfs: `/dev/mmcblk1p2`
- Boot partition: `/dev/mmcblk1p1`
- eMMC host: `d0074000.mmc`
- eMMC block device: `/dev/mmcblk2`
- eMMC size: `7818182656` bytes
- eMMC mode in runtime DTB: 1-bit bus, `max-frequency = <400000>`
- eMMC queue limits needed for reliable reads: `max_sectors_kb=4`,
  `nomerges=2`, default read-only

Keep eMMC checks read-only by default. Without the queue limits, normal merged
reads can still report `Input/output error`. After applying the queue limits,
`fdisk -l /dev/mmcblk2` and 1 MiB read tests from the start and end of the
device completed without new MMC I/O errors.

Do not add `amlogic,dram-access-quirk` to this GXL eMMC node. That DTB-only
test made the card enumerate but caused `mmcblk` probe to fail with `error
-22`, so `/dev/mmcblk2` was not created.
