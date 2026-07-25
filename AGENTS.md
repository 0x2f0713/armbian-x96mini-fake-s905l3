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

Keep eMMC checks read-only by default. The initial kernel partition probe
logged read I/O errors and no partition table was detected, although explicit
single-sector reads from the first, middle, and last tested sectors succeeded
after marking `/dev/mmcblk2` read-only.
