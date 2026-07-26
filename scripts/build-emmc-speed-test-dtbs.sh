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
DTB_NAME="${DTB_NAME:-meson-gxl-s905l3b-m302a.dtb}"
MMC_NODE="${MMC_NODE:-/soc/apb@d0000000/mmc@74000}"
FREQUENCIES="${FREQUENCIES:-1000000 2000000 5000000 10000000 20000000 25000000}"
BUS_WIDTH="${BUS_WIDTH:-1}"
MAX_REQUEST_BLOCKS="${MAX_REQUEST_BLOCKS:-8}"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-${ROOT}/artifacts/emmc-speed-tests}"

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

[ -d "${KERNEL_TREE}/.git" ] || die "kernel tree is not a Git checkout: ${KERNEL_TREE}"
command -v fdtget >/dev/null 2>&1 || die "fdtget is required"
command -v fdtput >/dev/null 2>&1 || die "fdtput is required"

tmp="$(mktemp -d /tmp/s905l3-emmc-speed.XXXXXX)"
cleanup() {
	git -C "${KERNEL_TREE}" worktree remove --force "${tmp}" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

git -C "${KERNEL_TREE}" worktree add --detach "${tmp}" HEAD >/dev/null
for patch in "${ROOT}"/patches/hdmi/*.patch; do
	git -C "${tmp}" apply "${patch}"
done

make -C "${tmp}" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" defconfig
make -C "${tmp}" ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" \
	"amlogic/${DTB_NAME}"

base_dtb="${tmp}/arch/${ARCH}/boot/dts/amlogic/${DTB_NAME}"
[ -f "${base_dtb}" ] || die "base DTB was not built: ${base_dtb}"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="${ARTIFACT_ROOT}/${stamp}-freq-sweep"
mkdir -p "${out}"

for freq in ${FREQUENCIES}; do
	case "${freq}" in
		*[!0-9]*|'') die "invalid frequency: ${freq}" ;;
	esac
	name="m302a-emmc-${freq}hz-bw${BUS_WIDTH}-req${MAX_REQUEST_BLOCKS}.dtb"
	cp "${base_dtb}" "${out}/${name}"
	fdtput -t i "${out}/${name}" "${MMC_NODE}" max-frequency "${freq}"
	fdtput -t i "${out}/${name}" "${MMC_NODE}" bus-width "${BUS_WIDTH}"
	fdtput -t i "${out}/${name}" "${MMC_NODE}" amlogic,max-request-blocks "${MAX_REQUEST_BLOCKS}"
	printf '%s bus=%s freq=%s req=%s\n' "${name}" \
		"$(fdtget "${out}/${name}" "${MMC_NODE}" bus-width)" \
		"$(fdtget "${out}/${name}" "${MMC_NODE}" max-frequency)" \
		"$(fdtget "${out}/${name}" "${MMC_NODE}" amlogic,max-request-blocks)"
done

cat >"${out}/README.md" <<EOF
# S905L3 eMMC Frequency Sweep

These DTBs start from the HDMI/eMMC/Wi-Fi/LED patch stack and only change
\`${MMC_NODE}/max-frequency\`. They keep the safer settings:

- \`bus-width = <${BUS_WIDTH}>\`
- no \`cap-mmc-highspeed\`, \`mmc-ddr-1_8v\`, or \`mmc-hs200-1_8v\`
- \`amlogic,max-request-blocks = <${MAX_REQUEST_BLOCKS}>\`

Test in ascending frequency order. After each reboot, run:

\`\`\`sh
sh ./benchmark-emmc-read.sh
\`\`\`

A good candidate must keep HDMI, Wi-Fi, LEDs, and eMMC read checks working with
no new eMMC errors. Do not test wider bus or high-speed modes until a higher
legacy frequency is proven stable.
EOF

cp "${ROOT}/scripts/benchmark-emmc-read.sh" "${out}/benchmark-emmc-read.sh"

(
	cd "${out}"
	sha256sum *.dtb README.md benchmark-emmc-read.sh >SHA256SUMS
)

printf 'artifact_dir=%s\n' "${out}"
