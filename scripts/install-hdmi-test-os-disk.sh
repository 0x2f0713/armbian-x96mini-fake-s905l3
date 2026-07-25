#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
  install-hdmi-test-os-disk.sh --root-dir PATH --boot-dir PATH --modules-tar PATH
      [--kernel PATH] [--dtb PATH] [--dtb-relpath PATH] [--kernel-release RELEASE]
      [--backup-root PATH]

Installs a locally built HDMI test kernel onto an offline Armbian OS disk.
The BOOT and ROOTFS partitions must already be mounted. The script extracts
matching modules into ROOTFS, backs up replaced boot files into ROOTFS, bind
mounts BOOT as ROOTFS/boot, runs depmod and update-initramfs in the chroot,
then writes BOOT/uInitrd from BOOT/initrd.img-RELEASE.
EOF
}

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

need_root() {
	[ "$(id -u)" -eq 0 ] || die "run as root"
}

uenv_fdt_relpath() {
	local uenv=${1%/}/uEnv.txt
	[ -f "${uenv}" ] || return 1
	sed -n 's/^FDT=//p' "${uenv}" | tail -n 1 | sed 's#^/##'
}

modules_tar_release() {
	tar -tf "$1" |
		sed -n 's#^\./lib/modules/\([^/][^/]*\)/.*#\1#p; s#^lib/modules/\([^/][^/]*\)/.*#\1#p' |
		head -n 1
}

bind_mounts=()

bind_mount() {
	local source=$1
	local target=$2

	mkdir -p "${target}"
	if mountpoint -q "${target}"; then
		return
	fi
	mount --bind "${source}" "${target}"
	bind_mounts+=("${target}")
}

cleanup() {
	local i

	for ((i = ${#bind_mounts[@]} - 1; i >= 0; i--)); do
		umount "${bind_mounts[$i]}" >/dev/null 2>&1 || true
	done
}

root_dir=
boot_dir=
modules_tar=
kernel_path=
dtb_path=
dtb_relpath=
kernel_release=
backup_root=

while [ "$#" -gt 0 ]; do
	case "$1" in
		--root-dir)
			shift
			[ "$#" -gt 0 ] || die "--root-dir needs a path"
			root_dir=$1
			;;
		--boot-dir)
			shift
			[ "$#" -gt 0 ] || die "--boot-dir needs a path"
			boot_dir=$1
			;;
		--modules-tar)
			shift
			[ "$#" -gt 0 ] || die "--modules-tar needs a path"
			modules_tar=$1
			;;
		--kernel)
			shift
			[ "$#" -gt 0 ] || die "--kernel needs a path"
			kernel_path=$1
			;;
		--dtb)
			shift
			[ "$#" -gt 0 ] || die "--dtb needs a path"
			dtb_path=$1
			;;
		--dtb-relpath)
			shift
			[ "$#" -gt 0 ] || die "--dtb-relpath needs a path"
			dtb_relpath=${1#/}
			;;
		--kernel-release)
			shift
			[ "$#" -gt 0 ] || die "--kernel-release needs a value"
			kernel_release=$1
			;;
		--backup-root)
			shift
			[ "$#" -gt 0 ] || die "--backup-root needs a path"
			backup_root=$1
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			die "unknown argument: $1"
			;;
	esac
	shift
done

need_root
[ -n "${root_dir}" ] || die "--root-dir is required"
[ -n "${boot_dir}" ] || die "--boot-dir is required"
[ -n "${modules_tar}" ] || die "--modules-tar is required"
[ -d "${root_dir}" ] || die "root dir not found: ${root_dir}"
[ -d "${boot_dir}" ] || die "boot dir not found: ${boot_dir}"
[ -f "${modules_tar}" ] || die "modules tarball not found: ${modules_tar}"
[ -z "${kernel_path}" ] || [ -f "${kernel_path}" ] || die "kernel not found: ${kernel_path}"
[ -z "${dtb_path}" ] || [ -f "${dtb_path}" ] || die "dtb not found: ${dtb_path}"
[ -x "${root_dir}/usr/sbin/update-initramfs" ] || die "update-initramfs missing in rootfs"
command -v chroot >/dev/null 2>&1 || die "chroot is required"
command -v mkimage >/dev/null 2>&1 || die "mkimage is required"

if [ -z "${kernel_release}" ]; then
	kernel_release=$(modules_tar_release "${modules_tar}")
fi
[ -n "${kernel_release}" ] || die "could not derive kernel release from modules tarball"

if [ -z "${dtb_relpath}" ] && [ -n "${dtb_path}" ]; then
	dtb_relpath=$(uenv_fdt_relpath "${boot_dir}" || true)
fi
[ -z "${dtb_path}" ] || [ -n "${dtb_relpath}" ] || die "could not derive DTB path; pass --dtb-relpath"

stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup_root=${backup_root:-${root_dir%/}/root/s905l3-hdmi-os-disk-backups}
backup_dir=${backup_root%/}/${stamp}-${kernel_release}
mkdir -p "${backup_dir}/boot"

for file in zImage uInitrd uEnv.txt "initrd.img-${kernel_release}"; do
	if [ -e "${boot_dir%/}/${file}" ]; then
		cp -a "${boot_dir%/}/${file}" "${backup_dir}/boot/${file}"
	fi
done
if [ -n "${dtb_relpath}" ] && [ -e "${boot_dir%/}/${dtb_relpath}" ]; then
	mkdir -p "${backup_dir}/boot/$(dirname "${dtb_relpath}")"
	cp -a "${boot_dir%/}/${dtb_relpath}" "${backup_dir}/boot/${dtb_relpath}"
fi
if [ -e "${root_dir%/}/lib/modules/${kernel_release}" ]; then
	mv "${root_dir%/}/lib/modules/${kernel_release}" "${backup_dir}/modules-${kernel_release}"
fi

tar -C "${root_dir}" -xpf "${modules_tar}"
chown -R root:root "${root_dir%/}/lib/modules/${kernel_release}"

if [ -n "${kernel_path}" ]; then
	cp -a "${kernel_path}" "${boot_dir%/}/zImage"
fi
if [ -n "${dtb_path}" ]; then
	mkdir -p "${boot_dir%/}/$(dirname "${dtb_relpath}")"
	cp -a "${dtb_path}" "${boot_dir%/}/${dtb_relpath}"
fi

trap cleanup EXIT INT TERM
bind_mount /dev "${root_dir%/}/dev"
bind_mount /proc "${root_dir%/}/proc"
bind_mount /sys "${root_dir%/}/sys"
bind_mount /run "${root_dir%/}/run"
bind_mount "${boot_dir}" "${root_dir%/}/boot"

chroot "${root_dir}" depmod -a "${kernel_release}"
if [ -e "${boot_dir%/}/initrd.img-${kernel_release}" ]; then
	chroot "${root_dir}" update-initramfs -u -k "${kernel_release}"
else
	chroot "${root_dir}" update-initramfs -c -k "${kernel_release}"
fi

mkimage -A arm64 -O linux -T ramdisk -C gzip -n uInitrd \
	-d "${boot_dir%/}/initrd.img-${kernel_release}" \
	"${boot_dir%/}/uInitrd"

sync
cleanup
trap - EXIT

printf 'kernel_release=%s\n' "${kernel_release}"
printf 'backup_dir=%s\n' "${backup_dir}"
printf 'installed_modules=%s\n' "${root_dir%/}/lib/modules/${kernel_release}"
printf 'installed_uinitrd=%s\n' "${boot_dir%/}/uInitrd"
