#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
KERNEL_TREE="${KERNEL_TREE:-${ROOT}/ophub-amlogic-s9xxx-armbian/compile-kernel/kernel/linux-6.18.y}"
LOCAL_ARM_GNU_PREFIX="${ROOT}/downloads/toolchains/extracted/arm-gnu-toolchain-15.2.rel1-aarch64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-"
if [ -z "${CROSS_COMPILE+x}" ]; then
	if [ -x "${LOCAL_ARM_GNU_PREFIX}gcc" ]; then
		CROSS_COMPILE="${LOCAL_ARM_GNU_PREFIX}"
	elif command -v aarch64-none-linux-gnu-gcc >/dev/null 2>&1; then
		CROSS_COMPILE="aarch64-none-linux-gnu-"
	else
		CROSS_COMPILE="aarch64-linux-gnu-"
	fi
fi
ARCH="${ARCH:-arm64}"

if [ ! -d "${KERNEL_TREE}/.git" ]; then
	echo "Kernel tree is not a Git checkout: ${KERNEL_TREE}" >&2
	exit 1
fi

TMP="$(mktemp -d /tmp/s905l3-hdmi-validate.XXXXXX)"
cleanup() {
	git -C "${KERNEL_TREE}" worktree remove --force "${TMP}" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

git -C "${KERNEL_TREE}" worktree add --detach "${TMP}" HEAD >/dev/null
for patch in "${ROOT}"/patches/hdmi/*.patch; do
	git -C "${TMP}" apply "${patch}"
done
git -C "${TMP}" diff --check

make -C "${TMP}" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" defconfig
"${TMP}/scripts/config" --file "${TMP}/.config" \
	--enable DRM \
	--enable DRM_MESON \
	--enable DRM_MESON_DW_HDMI \
	--enable DRM_DW_HDMI \
	--enable DRM_DW_HDMI_CEC \
	--enable OF \
	--enable COMMON_CLK \
	--enable REGMAP_MMIO
make -C "${TMP}" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" olddefconfig

make -C "${TMP}" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" -j"$(nproc)" \
	drivers/gpu/drm/meson/meson_dw_hdmi.o \
	drivers/gpu/drm/meson/meson_drv.o \
	amlogic/meson-gxl-s905l3b-m302a.dtb

ls -lh \
	"${TMP}/drivers/gpu/drm/meson/meson_dw_hdmi.o" \
	"${TMP}/drivers/gpu/drm/meson/meson_drv.o" \
	"${TMP}/arch/arm64/boot/dts/amlogic/meson-gxl-s905l3b-m302a.dtb"
