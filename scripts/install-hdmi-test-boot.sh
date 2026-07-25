#!/bin/sh
set -eu

SERVICE_NAME=s905l3-hdmi-rollback.service
INSTALL_PATH=/usr/local/sbin/s905l3-hdmi-test
SERVICE_PATH=/etc/systemd/system/${SERVICE_NAME}
STATE_DIR=/var/lib/s905l3-hdmi-test
STATE_FILE=${STATE_DIR}/state
CONFIRM_FILE=${STATE_DIR}/confirmed

usage() {
	cat <<'EOF'
Usage:
  install-hdmi-test-boot.sh --kernel PATH [--initrd PATH] [--dtb PATH]
      [--boot-dir /boot] [--dtb-relpath dtb/amlogic/meson-gxl-s905l3b-m302a.dtb]
      [--rollback-delay SECONDS] [--no-reboot] [--force]

  install-hdmi-test-boot.sh --confirm
  install-hdmi-test-boot.sh --rollback [--no-reboot]

Installs a test kernel/DTB into an Armbian boot partition and arms a
systemd rollback service. After the test boot, run --confirm before the
rollback delay expires. If not confirmed, the previous boot files are
restored and the board reboots.
EOF
}

die() {
	echo "error: $*" >&2
	exit 1
}

need_root() {
	[ "$(id -u)" -eq 0 ] || die "run as root"
}

quote_sh() {
	printf "'"
	printf "%s" "$1" | sed "s/'/'\\\\''/g"
	printf "'"
}

uenv_fdt_relpath() {
	uenv=${1%/}/uEnv.txt
	[ -f "${uenv}" ] || return 1
	sed -n 's/^FDT=//p' "${uenv}" | tail -n 1 | sed 's#^/##'
}

load_state() {
	[ -f "${STATE_FILE}" ] || die "no rollback state at ${STATE_FILE}"
	# The state file is written by this script under /var/lib as root.
	. "${STATE_FILE}"
	: "${BOOT_DIR:?}"
	: "${BACKUP_DIR:?}"
	: "${DTB_REL_PATH:=}"
}

restore_previous_boot() {
	load_state

	[ -f "${BACKUP_DIR}/zImage" ] && cp -f "${BACKUP_DIR}/zImage" "${BOOT_DIR}/zImage"
	[ -f "${BACKUP_DIR}/uInitrd" ] && cp -f "${BACKUP_DIR}/uInitrd" "${BOOT_DIR}/uInitrd"
	[ -f "${BACKUP_DIR}/uEnv.txt" ] && cp -f "${BACKUP_DIR}/uEnv.txt" "${BOOT_DIR}/uEnv.txt"

	if [ -n "${DTB_REL_PATH}" ] && [ -f "${BACKUP_DIR}/dtb" ]; then
		mkdir -p "${BOOT_DIR}/$(dirname "${DTB_REL_PATH}")"
		cp -f "${BACKUP_DIR}/dtb" "${BOOT_DIR}/${DTB_REL_PATH}"
	fi

	sync
}

disable_service() {
	if command -v systemctl >/dev/null 2>&1; then
		systemctl disable --now "${SERVICE_NAME}" >/dev/null 2>&1 || true
		rm -f "${SERVICE_PATH}"
		systemctl daemon-reload >/dev/null 2>&1 || true
	fi
}

remove_service_registration() {
	if command -v systemctl >/dev/null 2>&1; then
		systemctl disable "${SERVICE_NAME}" >/dev/null 2>&1 || true
		rm -f "${SERVICE_PATH}"
		systemctl daemon-reload >/dev/null 2>&1 || true
	fi
}

confirm_boot() {
	need_root
	mkdir -p "${STATE_DIR}"
	touch "${CONFIRM_FILE}"
	disable_service
	echo "HDMI test boot confirmed. Rollback service disabled."
}

manual_rollback() {
	need_root
	restore_previous_boot
	rm -f "${CONFIRM_FILE}"
	disable_service
	echo "Previous boot files restored from ${BACKUP_DIR}."
	if [ "${no_reboot}" -eq 0 ]; then
		reboot
	fi
}

service_rollback() {
	need_root
	load_state
	delay=${ROLLBACK_DELAY_SECONDS:-300}
	sleep "${delay}"
	if [ -f "${CONFIRM_FILE}" ]; then
		exit 0
	fi

	restore_previous_boot
	remove_service_registration
	echo "HDMI test was not confirmed; previous boot files restored."
	reboot
}

install_service() {
	if [ "$0" != "${INSTALL_PATH}" ]; then
		install -m 0755 "$0" "${INSTALL_PATH}"
	fi
	cat >"${SERVICE_PATH}" <<EOF
[Unit]
Description=S905L3 HDMI test rollback
After=multi-user.target

[Service]
Type=simple
ExecStart=${INSTALL_PATH} --service-rollback

[Install]
WantedBy=multi-user.target
EOF
	systemctl daemon-reload
	systemctl enable "${SERVICE_NAME}" >/dev/null
}

write_state() {
	{
		printf 'BOOT_DIR=%s\n' "$(quote_sh "${boot_dir}")"
		printf 'BACKUP_DIR=%s\n' "$(quote_sh "${backup_dir}")"
		printf 'DTB_REL_PATH=%s\n' "$(quote_sh "${dtb_relpath}")"
		printf 'ROLLBACK_DELAY_SECONDS=%s\n' "$(quote_sh "${rollback_delay}")"
	} >"${STATE_FILE}"
}

install_test_boot() {
	need_root
	[ -n "${kernel_path}" ] || die "--kernel is required"
	[ -f "${kernel_path}" ] || die "kernel not found: ${kernel_path}"
	[ -z "${initrd_path}" ] || [ -f "${initrd_path}" ] || die "initrd not found: ${initrd_path}"
	[ -z "${dtb_path}" ] || [ -f "${dtb_path}" ] || die "dtb not found: ${dtb_path}"
	[ -d "${boot_dir}" ] || die "boot directory not found: ${boot_dir}"
	command -v systemctl >/dev/null 2>&1 || die "systemd is required for automatic rollback"

	if [ -z "${dtb_relpath}" ] && [ -n "${dtb_path}" ]; then
		dtb_relpath=$(uenv_fdt_relpath "${boot_dir}" || true)
	fi
	[ -z "${dtb_path}" ] || [ -n "${dtb_relpath}" ] || die "could not derive DTB path; pass --dtb-relpath"

	if [ -f "${STATE_FILE}" ] && [ ! -f "${CONFIRM_FILE}" ] && [ "${force}" -eq 0 ]; then
		die "an unconfirmed HDMI test already exists; run --confirm, --rollback, or --force"
	fi

	mkdir -p "${STATE_DIR}"
	rm -f "${CONFIRM_FILE}"
	backup_dir=${boot_dir%/}/hdmi-test-backups/$(date -u +%Y%m%dT%H%M%SZ)
	mkdir -p "${backup_dir}"

	[ -f "${boot_dir}/zImage" ] || die "existing ${boot_dir}/zImage not found"
	cp -f "${boot_dir}/zImage" "${backup_dir}/zImage"
	[ ! -f "${boot_dir}/uInitrd" ] || cp -f "${boot_dir}/uInitrd" "${backup_dir}/uInitrd"
	[ ! -f "${boot_dir}/uEnv.txt" ] || cp -f "${boot_dir}/uEnv.txt" "${backup_dir}/uEnv.txt"
	if [ -n "${dtb_path}" ] && [ -f "${boot_dir}/${dtb_relpath}" ]; then
		cp -f "${boot_dir}/${dtb_relpath}" "${backup_dir}/dtb"
	fi

	write_state
	install_service

	cp -f "${kernel_path}" "${boot_dir}/zImage"
	[ -z "${initrd_path}" ] || cp -f "${initrd_path}" "${boot_dir}/uInitrd"
	if [ -n "${dtb_path}" ]; then
		mkdir -p "${boot_dir}/$(dirname "${dtb_relpath}")"
		cp -f "${dtb_path}" "${boot_dir}/${dtb_relpath}"
	fi
	sync

	echo "Installed HDMI test boot files."
	echo "Backup: ${backup_dir}"
	echo "After reboot, run: ${INSTALL_PATH} --confirm"
	if [ "${no_reboot}" -eq 0 ]; then
		reboot
	fi
}

mode=install
kernel_path=
initrd_path=
dtb_path=
boot_dir=/boot
dtb_relpath=
rollback_delay=300
no_reboot=0
force=0

while [ "$#" -gt 0 ]; do
	case "$1" in
		--kernel)
			shift
			[ "$#" -gt 0 ] || die "--kernel needs a path"
			kernel_path=$1
			;;
		--initrd)
			shift
			[ "$#" -gt 0 ] || die "--initrd needs a path"
			initrd_path=$1
			;;
		--dtb)
			shift
			[ "$#" -gt 0 ] || die "--dtb needs a path"
			dtb_path=$1
			;;
		--boot-dir)
			shift
			[ "$#" -gt 0 ] || die "--boot-dir needs a path"
			boot_dir=$1
			;;
		--dtb-relpath)
			shift
			[ "$#" -gt 0 ] || die "--dtb-relpath needs a path"
			dtb_relpath=${1#/}
			;;
		--rollback-delay)
			shift
			[ "$#" -gt 0 ] || die "--rollback-delay needs seconds"
			rollback_delay=$1
			case "${rollback_delay}" in
				*[!0-9]*|'') die "--rollback-delay must be a positive integer" ;;
			esac
			;;
		--confirm)
			mode=confirm
			;;
		--rollback)
			mode=rollback
			;;
		--service-rollback)
			mode=service_rollback
			;;
		--no-reboot)
			no_reboot=1
			;;
		--force)
			force=1
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

case "${mode}" in
	install) install_test_boot ;;
	confirm) confirm_boot ;;
	rollback) manual_rollback ;;
	service_rollback) service_rollback ;;
esac
