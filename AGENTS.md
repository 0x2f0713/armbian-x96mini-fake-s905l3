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
