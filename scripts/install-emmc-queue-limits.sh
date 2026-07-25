#!/bin/sh
set -eu

SERVICE_NAME=s905l3-emmc-queue-limits.service
SERVICE_PATH=/etc/systemd/system/${SERVICE_NAME}
INSTALL_PATH=/usr/local/sbin/s905l3-emmc-queue-limits
UDEV_RULE_PATH=/etc/udev/rules.d/99-s905l3-emmc-queue-limits.rules

HOST_MATCH=${HOST_MATCH:-d0074000.mmc}
MAX_SECTORS_KB=${MAX_SECTORS_KB:-4}
NOMERGES=${NOMERGES:-2}
READ_AHEAD_KB=${READ_AHEAD_KB:-0}
READ_ONLY=${READ_ONLY:-1}
WAIT_SECONDS=${WAIT_SECONDS:-30}

usage() {
	cat <<'EOF'
Usage:
  install-emmc-queue-limits.sh --install
  install-emmc-queue-limits.sh --apply
  install-emmc-queue-limits.sh --status
  install-emmc-queue-limits.sh --uninstall

Installs or applies conservative block queue limits for the internal eMMC
attached to the Amlogic d0074000.mmc host. The defaults are intentionally slow
and read-only:

  MAX_SECTORS_KB=4
  NOMERGES=2
  READ_AHEAD_KB=0
  READ_ONLY=1

Override those values in the environment if needed.
EOF
}

die() {
	echo "error: $*" >&2
	exit 1
}

need_root() {
	[ "$(id -u)" -eq 0 ] || die "run as root"
}

find_emmc_blocks() {
	local block name path

	for block in /sys/block/mmcblk*; do
		[ -e "${block}" ] || continue
		name=$(basename "${block}")
		case "${name}" in
			*boot*|*rpmb*) continue ;;
		esac

		path=$(readlink -f "${block}")
		case "${path}" in
			*"${HOST_MATCH}"*) echo "${name}" ;;
		esac
	done
}

wait_for_emmc_blocks() {
	local waited=0

	while :; do
		if find_emmc_blocks | grep -q .; then
			return 0
		fi
		[ "${waited}" -ge "${WAIT_SECONDS}" ] && return 1
		sleep 1
		waited=$((waited + 1))
	done
}

write_attr() {
	local path=$1
	local value=$2

	[ -e "${path}" ] || return 0
	printf '%s\n' "${value}" >"${path}" 2>/dev/null || true
}

apply_one() {
	local name=$1
	local sys=/sys/block/${name}
	local dev=/dev/${name}

	[ -d "${sys}" ] || return 0

	if [ "${READ_ONLY}" = 1 ] && [ -b "${dev}" ]; then
		blockdev --setro "${dev}" 2>/dev/null || true
	fi

	write_attr "${sys}/queue/max_sectors_kb" "${MAX_SECTORS_KB}"
	write_attr "${sys}/queue/nomerges" "${NOMERGES}"
	write_attr "${sys}/queue/read_ahead_kb" "${READ_AHEAD_KB}"

	printf 'block=%s\n' "${name}"
	printf 'path=%s\n' "$(readlink -f "${sys}")"
	printf 'ro=%s\n' "$(cat "${sys}/ro" 2>/dev/null || echo unknown)"
	printf 'max_sectors_kb=%s\n' "$(cat "${sys}/queue/max_sectors_kb" 2>/dev/null || echo unknown)"
	printf 'nomerges=%s\n' "$(cat "${sys}/queue/nomerges" 2>/dev/null || echo unknown)"
	printf 'read_ahead_kb=%s\n' "$(cat "${sys}/queue/read_ahead_kb" 2>/dev/null || echo unknown)"
}

apply_limits() {
	local block found=0

	wait_for_emmc_blocks || die "no eMMC block found under ${HOST_MATCH}"
	for block in $(find_emmc_blocks); do
		found=1
		apply_one "${block}"
	done
	[ "${found}" -eq 1 ] || die "no eMMC block found under ${HOST_MATCH}"
}

status_limits() {
	local block found=0

	for block in $(find_emmc_blocks); do
		found=1
		apply_one "${block}"
	done
	[ "${found}" -eq 1 ] || die "no eMMC block found under ${HOST_MATCH}"
}

install_files() {
	need_root
	install -m 0755 "$0" "${INSTALL_PATH}"

	cat >"${SERVICE_PATH}" <<EOF
[Unit]
Description=S905L3 internal eMMC queue limits
After=systemd-udevd.service

[Service]
Type=oneshot
ExecStart=${INSTALL_PATH} --apply

[Install]
WantedBy=multi-user.target
EOF

	cat >"${UDEV_RULE_PATH}" <<EOF
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="mmcblk[0-9]", ENV{DEVPATH}=="*${HOST_MATCH}*", ATTR{queue/max_sectors_kb}="${MAX_SECTORS_KB}", ATTR{queue/nomerges}="${NOMERGES}", ATTR{queue/read_ahead_kb}="${READ_AHEAD_KB}"
EOF

	if command -v udevadm >/dev/null 2>&1; then
		udevadm control --reload-rules >/dev/null 2>&1 || true
		udevadm trigger --subsystem-match=block --sysname-match='mmcblk*' >/dev/null 2>&1 || true
	fi

	if command -v systemctl >/dev/null 2>&1; then
		systemctl daemon-reload
		systemctl enable "${SERVICE_NAME}" >/dev/null
		systemctl restart "${SERVICE_NAME}"
	else
		"${INSTALL_PATH}" --apply
	fi
}

uninstall_files() {
	need_root
	if command -v systemctl >/dev/null 2>&1; then
		systemctl disable --now "${SERVICE_NAME}" >/dev/null 2>&1 || true
		rm -f "${SERVICE_PATH}"
		systemctl daemon-reload
	fi
	rm -f "${UDEV_RULE_PATH}" "${INSTALL_PATH}"
	if command -v udevadm >/dev/null 2>&1; then
		udevadm control --reload-rules >/dev/null 2>&1 || true
	fi
}

case "${1:---apply}" in
	--install)
		install_files
		;;
	--apply)
		need_root
		apply_limits
		;;
	--status)
		status_limits
		;;
	--uninstall)
		uninstall_files
		;;
	-h|--help)
		usage
		;;
	*)
		usage >&2
		exit 1
		;;
esac
