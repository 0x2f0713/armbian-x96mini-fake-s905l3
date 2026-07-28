#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
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
LOCALVERSION="${LOCALVERSION:--x96gxlx2}"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-${ROOT}/artifacts/hdmi-gxlx2}"
DTB_NAME="${DTB_NAME:-meson-gxl-s905l3b-m302a.dtb}"
DISABLE_BTF="${DISABLE_BTF:-true}"
DISABLE_MESON_DRM="${DISABLE_MESON_DRM:-false}"
BUILD_MODULES="${BUILD_MODULES:-true}"
BUILD_WIFI="${BUILD_WIFI:-true}"
WIFI_DRIVER_DIR="${WIFI_DRIVER_DIR:-${ROOT}/src/rtl8189ES_linux}"
HOST_CPUS="${HOST_CPUS:-$(nproc)}"
JOBS="${JOBS:-$((HOST_CPUS * 2))}"
WIFI_JOBS="${WIFI_JOBS:-${JOBS}}"
USE_CCACHE="${USE_CCACHE:-auto}"
CCACHE_DIR="${CCACHE_DIR:-${ROOT}/.cache/ccache}"
CCACHE_WRAPPER_DIR="${CCACHE_WRAPPER_DIR:-${ROOT}/.cache/ccache-wrappers}"
KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-s905l3}"
KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-builder}"

patches=("${ROOT}"/patches/hdmi/*.patch)

touched=(
	Documentation/devicetree/bindings/display/amlogic,meson-dw-hdmi.yaml
	Documentation/devicetree/bindings/mmc/amlogic,meson-gx-mmc.yaml
	drivers/gpu/drm/meson/meson_drv.c
	drivers/gpu/drm/meson/meson_dw_hdmi.c
	drivers/mmc/host/meson-gx-mmc.c
	arch/arm64/boot/dts/amlogic/meson-gxl-s905l3b-m302a.dts
)

tmp_paths=()
wifi_build_started=false

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

cleanup() {
	local path

	if [ "${wifi_build_started}" = "true" ] && [ -n "${kernel_release:-}" ]; then
		make -C "${WIFI_DRIVER_DIR}" \
			ARCH="${ARCH}" \
			CROSS_COMPILE="${effective_cross_compile:-${CROSS_COMPILE}}" \
			KSRC="${KERNEL_TREE}" \
			KVER="${kernel_release}" \
			clean >/dev/null 2>&1 || true
	fi

	git -C "${KERNEL_TREE}" restore -- "${touched[@]}" >/dev/null 2>&1 || true
	for path in "${tmp_paths[@]}"; do
		rm -rf "${path}"
	done
}

check_touched_clean() {
	local dirty=0
	local path

	for path in "${touched[@]}"; do
		if ! git -C "${KERNEL_TREE}" cat-file -e "HEAD:${path}" 2>/dev/null; then
			printf 'tracked file missing from kernel HEAD: %s\n' "${path}" >&2
			dirty=1
			continue
		fi

		if ! git -C "${KERNEL_TREE}" show "HEAD:${path}" | cmp -s - "${KERNEL_TREE}/${path}"; then
			printf 'tracked HDMI patch target differs from kernel HEAD: %s\n' "${path}" >&2
			dirty=1
		fi
	done

	if [ "${dirty}" -ne 0 ]; then
		die "kernel tree has tracked HDMI patch-target changes; refusing in-place build"
	fi
}

ccache_cross_assembler_works() {
	local test_path="$1"
	local test_cross_compile="$2"

	env \
		CCACHE_DIR="${CCACHE_DIR}" \
		CCACHE_BASEDIR="${ROOT}" \
		PATH="${test_path}" \
		"${KERNEL_TREE}/scripts/as-version.sh" "${test_cross_compile}gcc" \
		>/dev/null 2>&1
}

[ -d "${KERNEL_TREE}/.git" ] || die "kernel tree is not a Git checkout: ${KERNEL_TREE}"
[ -x "${KERNEL_TREE}/scripts/config" ] || die "kernel scripts/config is missing; run a kernel prepare/config step first"

case "${BUILD_MODULES}" in
	true|false) ;;
	*) die "BUILD_MODULES must be true or false" ;;
esac

case "${BUILD_WIFI}" in
	true|false) ;;
	*) die "BUILD_WIFI must be true or false" ;;
esac

check_touched_clean

ccache_enabled=false
effective_cross_compile="${CROSS_COMPILE}"
case "${USE_CCACHE}" in
	true|auto)
		if command -v ccache >/dev/null 2>&1; then
			ccache_path="$(command -v ccache)"
			toolchain_path="${PATH}"
			wrapper_prefix="${CROSS_COMPILE}"

			case "${CROSS_COMPILE}" in
				*/*)
					toolchain_bin="$(dirname "${CROSS_COMPILE}gcc")"
					wrapper_prefix="$(basename "${CROSS_COMPILE}")"
					toolchain_path="${toolchain_bin}:${toolchain_path}"
					;;
			esac

			mkdir -p "${CCACHE_DIR}"
			mkdir -p "${CCACHE_WRAPPER_DIR}"
			ln -sf "${ccache_path}" "${CCACHE_WRAPPER_DIR}/${wrapper_prefix}gcc"
			toolchain_path="${CCACHE_WRAPPER_DIR}:${toolchain_path}"

			if ccache_cross_assembler_works "${toolchain_path}" "${wrapper_prefix}"; then
				export CCACHE_DIR
				export CCACHE_BASEDIR="${ROOT}"
				export PATH="${toolchain_path}"
				effective_cross_compile="${wrapper_prefix}"
				ccache_enabled=true
			elif [ "${USE_CCACHE}" = "true" ]; then
				die "USE_CCACHE=true requested but the ccache cross-compiler wrapper is not usable"
			fi
		elif [ "${USE_CCACHE}" = "true" ]; then
			die "USE_CCACHE=true requested but ccache is not available"
		fi
		;;
	false)
		;;
	*)
		die "USE_CCACHE must be auto, true, or false"
		;;
esac

make_args=(
	ARCH="${ARCH}"
	CROSS_COMPILE="${effective_cross_compile}"
	LOCALVERSION="${LOCALVERSION}"
	KBUILD_BUILD_USER="${KBUILD_BUILD_USER}"
	KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST}"
)

for patch in "${patches[@]}"; do
	git -C "${KERNEL_TREE}" apply --check "${patch}"
done

trap cleanup EXIT INT TERM

for patch in "${patches[@]}"; do
	git -C "${KERNEL_TREE}" apply "${patch}"
done

if [ "${DISABLE_BTF}" = "true" ]; then
	"${KERNEL_TREE}/scripts/config" --file "${KERNEL_TREE}/.config" \
		--disable DEBUG_INFO_BTF \
		--disable DEBUG_INFO_BTF_MODULES
fi

if [ "${DISABLE_MESON_DRM}" = "true" ]; then
	"${KERNEL_TREE}/scripts/config" --file "${KERNEL_TREE}/.config" \
		--disable DRM_MESON \
		--disable DRM_MESON_DW_HDMI \
		--disable DRM_MESON_DW_MIPI_DSI
else
	"${KERNEL_TREE}/scripts/config" --file "${KERNEL_TREE}/.config" \
		--enable DRM \
		--enable DRM_MESON \
		--enable DRM_MESON_DW_HDMI \
		--enable DRM_DW_HDMI \
		--enable DRM_DW_HDMI_CEC \
		--enable OF \
		--enable COMMON_CLK \
		--enable REGMAP_MMIO
fi

"${KERNEL_TREE}/scripts/config" --file "${KERNEL_TREE}/.config" \
	--disable LOCALVERSION_AUTO

make -C "${KERNEL_TREE}" \
	"${make_args[@]}" \
	olddefconfig

make -C "${KERNEL_TREE}" \
	"${make_args[@]}" \
	-j"${JOBS}" \
	Image \
	"amlogic/${DTB_NAME}"

kernel_release="$(
	make -s -C "${KERNEL_TREE}" \
		"${make_args[@]}" \
		kernelrelease
)"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="${ARTIFACT_ROOT}/${kernel_release}-${stamp}"
mkdir -p "${out}"

modules_tar_name=
if [ "${BUILD_MODULES}" = "true" ]; then
	module_stage="$(mktemp -d /tmp/s905l3-hdmi-modules.XXXXXX)"
	tmp_paths+=("${module_stage}")

	make -C "${KERNEL_TREE}" \
		"${make_args[@]}" \
		-j"${JOBS}" \
		modules

	make -C "${KERNEL_TREE}" \
		"${make_args[@]}" \
		INSTALL_MOD_PATH="${module_stage}" \
		INSTALL_MOD_STRIP=1 \
		modules_install

	modules_tar_name="modules-${kernel_release}.tar.gz"
	tar -C "${module_stage}" -czf "${out}/${modules_tar_name}" \
		"lib/modules/${kernel_release}"
fi

wifi_module_name=
if [ "${BUILD_WIFI}" = "true" ]; then
	[ -f "${WIFI_DRIVER_DIR}/Makefile" ] || die "RTL8189ES driver Makefile not found: ${WIFI_DRIVER_DIR}/Makefile"
	command -v modinfo >/dev/null 2>&1 || die "modinfo is required to validate the RTL8189ES module"

	wifi_build_started=true
	make -C "${WIFI_DRIVER_DIR}" \
		ARCH="${ARCH}" \
		CROSS_COMPILE="${effective_cross_compile}" \
		KSRC="${KERNEL_TREE}" \
		KVER="${kernel_release}" \
		clean
	make -C "${WIFI_DRIVER_DIR}" \
		ARCH="${ARCH}" \
		CROSS_COMPILE="${effective_cross_compile}" \
		KSRC="${KERNEL_TREE}" \
		KVER="${kernel_release}" \
		-j"${WIFI_JOBS}"

	[ -f "${WIFI_DRIVER_DIR}/8189es.ko" ] || die "RTL8189ES build did not produce 8189es.ko"
	wifi_vermagic="$(modinfo -F vermagic "${WIFI_DRIVER_DIR}/8189es.ko" | awk '{print $1}')"
	[ "${wifi_vermagic}" = "${kernel_release}" ] || die "8189es.ko vermagic ${wifi_vermagic} does not match ${kernel_release}"

	wifi_module_name=8189es.ko
	cp "${WIFI_DRIVER_DIR}/8189es.ko" "${out}/${wifi_module_name}"
fi

cp "${KERNEL_TREE}/arch/${ARCH}/boot/Image" "${out}/zImage"
cp "${KERNEL_TREE}/arch/${ARCH}/boot/dts/amlogic/${DTB_NAME}" "${out}/${DTB_NAME}"
cp "${KERNEL_TREE}/.config" "${out}/config-${kernel_release}"
cp "${KERNEL_TREE}/System.map" "${out}/System.map-${kernel_release}"
cp "${ROOT}/scripts/install-hdmi-test-boot.sh" "${out}/install-hdmi-test-boot.sh"
cp "${ROOT}/scripts/install-hdmi-test-os-disk.sh" "${out}/install-hdmi-test-os-disk.sh"
if [ -n "${wifi_module_name}" ]; then
	cp "${ROOT}/scripts/install-8189es-module.sh" "${out}/install-8189es-module.sh"
fi

{
	if [ "${DISABLE_MESON_DRM}" = "true" ]; then
		printf '# S905L3 No-Meson-DRM Diagnostic Bundle\n\n'
	else
		printf '# S905L3 GXLX2 HDMI/eMMC Test Bundle\n\n'
	fi
	printf 'Kernel release: %s\n\n' "${kernel_release}"
	if [ "${DISABLE_BTF}" = "true" ]; then
		printf 'Build note: CONFIG_DEBUG_INFO_BTF is disabled in this artifact to avoid host resolve_btfids linkage failure. This does not change the Meson HDMI runtime path.\n\n'
	fi
	if [ "${DISABLE_MESON_DRM}" = "true" ]; then
		printf 'Diagnostic note: CONFIG_DRM_MESON is disabled. This artifact intentionally does not drive HDMI; it tests whether the same kernel/toolchain boots when the Meson display stack cannot bind.\n\n'
	fi
	printf 'Files:\n'
	if [ "${DISABLE_MESON_DRM}" = "true" ]; then
		printf -- '- zImage: arm64 Image built with Meson DRM disabled.\n'
		printf -- '- %s: M302A DTB using the same GXLX2 HDMI description; it is inert while CONFIG_DRM_MESON is disabled.\n' "${DTB_NAME}"
	else
		printf -- '- zImage: arm64 Image built with the experimental GXLX2 HDMI patch set and Meson eMMC request clamp.\n'
		printf -- '- %s: M302A DTB using amlogic,meson-gxlx2-dw-hdmi at 0xda800000, conservative eMMC settings, and X96 GPIO LEDs.\n' "${DTB_NAME}"
	fi
	printf -- '- config-%s: kernel config used for this build.\n' "${kernel_release}"
	printf -- '- System.map-%s: symbol map for diagnostics.\n' "${kernel_release}"
	printf -- '- install-hdmi-test-boot.sh: guarded board-side installer with automatic rollback.\n'
	printf -- '- install-hdmi-test-os-disk.sh: offline OS-disk installer that extracts matching modules and regenerates uInitrd.\n'
	if [ -n "${modules_tar_name}" ]; then
		printf -- '- %s: stripped module tree for /lib/modules/%s.\n' "${modules_tar_name}" "${kernel_release}"
	fi
	if [ -n "${wifi_module_name}" ]; then
		printf -- '- %s: RTL8189ES SDIO Wi-Fi module built for %s.\n' "${wifi_module_name}" "${kernel_release}"
		printf -- '- install-8189es-module.sh: module-only RTL8189ES installer; it does not replace the DTB.\n'
	fi
	printf '\nSuggested board-side test after restoring SSH:\n\n'
	if [ -n "${modules_tar_name}" ]; then
		printf '    sudo tar -C / -xpf ./%s\n' "${modules_tar_name}"
		printf '    sudo update-initramfs -c -k %s\n' "${kernel_release}"
		printf '    sudo ./install-hdmi-test-boot.sh --kernel ./zImage --dtb ./%s --rollback-delay 300\n\n' "${DTB_NAME}"
		if [ -n "${wifi_module_name}" ]; then
			printf '    sudo ./install-8189es-module.sh ./%s\n\n' "${wifi_module_name}"
		fi
		printf 'Offline OS-disk install from another ARM64 Linux host:\n\n'
		printf '    sudo ./install-hdmi-test-os-disk.sh \\\n'
		printf '      --root-dir /mnt/x96root-rw \\\n'
		printf '      --boot-dir /mnt/x96boot-rw \\\n'
		printf '      --modules-tar ./%s \\\n' "${modules_tar_name}"
		printf '      --kernel ./zImage \\\n'
		printf '      --dtb ./%s\n\n' "${DTB_NAME}"
	else
		printf '    sudo ./install-hdmi-test-boot.sh --kernel ./zImage --dtb ./%s --rollback-delay 300\n\n' "${DTB_NAME}"
		if [ -n "${wifi_module_name}" ]; then
			printf '    sudo ./install-8189es-module.sh ./%s\n\n' "${wifi_module_name}"
		fi
	fi
	printf 'Expected eMMC queue after boot: /sys/block/mmcblk2/queue/max_hw_sectors_kb = 4.\n\n'
	if [ -n "${wifi_module_name}" ]; then
		printf 'Expected Wi-Fi after module install: SDIO device 024C:8179 bound to rtl8189es with a single wlan0 interface present.\n\n'
	fi
	printf 'Expected LEDs after boot: /sys/class/leds/x96:blue:sys and /sys/class/leds/x96:blue:net.\n\n'
	printf 'Keep the kernel image, DTB, modules, and regenerated uInitrd on the same kernel release. A stale initrd/module tree can reset the board at the /init handoff even after HDMI has bound successfully.\n'
} >"${out}/README.md"

sha_files=(
	zImage
	"${DTB_NAME}"
	"config-${kernel_release}"
	"System.map-${kernel_release}"
	install-hdmi-test-boot.sh
	install-hdmi-test-os-disk.sh
	README.md
)
if [ -n "${modules_tar_name}" ]; then
	sha_files+=("${modules_tar_name}")
fi
if [ -n "${wifi_module_name}" ]; then
	sha_files+=("${wifi_module_name}" install-8189es-module.sh)
fi

(
	cd "${out}"
	sha256sum "${sha_files[@]}" >SHA256SUMS
)

tarball="${out}.tar.gz"
tar -C "${ARTIFACT_ROOT}" -czf "${tarball}" "$(basename "${out}")"
sha256sum "${tarball}" >"${tarball}.sha256"

cleanup
trap - EXIT

printf 'artifact_dir=%s\n' "${out}"
printf 'artifact_tar=%s\n' "${tarball}"
printf 'kernel_release=%s\n' "${kernel_release}"
printf 'build_user=%s\n' "${KBUILD_BUILD_USER}"
printf 'build_host=%s\n' "${KBUILD_BUILD_HOST}"
printf 'build_jobs=%s\n' "${JOBS}"
printf 'disable_meson_drm=%s\n' "${DISABLE_MESON_DRM}"
printf 'build_modules=%s\n' "${BUILD_MODULES}"
printf 'build_wifi=%s\n' "${BUILD_WIFI}"
if [ -n "${modules_tar_name}" ]; then
	printf 'modules_tar=%s\n' "${out}/${modules_tar_name}"
fi
if [ -n "${wifi_module_name}" ]; then
	printf 'wifi_module=%s\n' "${out}/${wifi_module_name}"
fi
if [ "${ccache_enabled}" = "true" ]; then
	printf 'ccache_dir=%s\n' "${CCACHE_DIR}"
fi
