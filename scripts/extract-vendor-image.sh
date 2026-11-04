#!/usr/bin/env bash
set -euo pipefail

usage() {
	echo "Usage: $0 <vendor.img> [output-directory]" >&2
}
[[ $# -ge 1 && $# -le 2 ]] || { usage; exit 2; }
image="$(readlink -f "$1")"
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$(readlink -m "${2:-${root_dir}/vendor}")"
[[ -f "${image}" ]] || { echo "Vendor image not found: ${image}" >&2; exit 1; }

# 7-Zip reads the ext4 partition inside this MBR image without root or a loop
# device. The mount fallback handles systems where 7z is unavailable.
extract_with_7z() {
	local archive_path="$1" destination="$2"
	7z e -so "${image}" "${archive_path}" > "${destination}" 2>/dev/null
}

rm -rf "${out}"
install -d "${out}/boot/dtb/rockchip" "${out}/boot" "${out}/rootfs"
chosen=""

if command -v 7z >/dev/null 2>&1; then
	if ! extract_with_7z boot/armbianEnv.txt "${out}/boot/armbianEnv.txt"; then
		rm -f "${out}/boot/armbianEnv.txt"
	fi
	if ! extract_with_7z boot/boot.cmd "${out}/boot/boot.cmd"; then
		rm -f "${out}/boot/boot.cmd"
	fi

	mapfile -t paths < <(7z l -slt "${image}" 2>/dev/null |
		sed -n 's/^Path = //p' |
		rg '^boot/(config-[^/]+|[^/]+\.dtb)$' || true)
	for path in "${paths[@]}"; do
		base="$(basename "${path}")"
		case "${base}" in
			config-*) extract_with_7z "${path}" "${out}/boot/${base}" || true ;;
		esac
	done

	if [[ -f "${out}/boot/armbianEnv.txt" ]]; then
		fdt="$(sed -n 's/^fdtfile=//p' "${out}/boot/armbianEnv.txt" | head -n1)"
		fdt="$(basename "${fdt}")"
		for path in "${paths[@]}"; do
			if [[ "$(basename "${path}")" == "${fdt}" ]]; then chosen="${path}"; break; fi
		done
	fi
	if [[ -z "${chosen}" ]]; then
		for path in "${paths[@]}"; do
			if [[ "${path}" == *3399*.dtb || "${path}" == *sm3399*.dtb ]]; then chosen="${path}"; break; fi
		done
	fi
	if [[ -n "${chosen}" ]]; then
		extract_with_7z "${chosen}" "${out}/boot/dtb/rockchip/rk3399-sm3399mb.dtb"
		printf '%s\n' "${chosen}" > "${out}/vendor-dtb-source"
	fi

	for path in etc/armbian-release etc/os-release; do
		base="$(basename "${path}")"
		extract_with_7z "${path}" "${out}/rootfs/${base}" 2>/dev/null || true
	done
else
	if (( EUID != 0 )); then exec sudo -- "$0" "$@"; fi
	for tool in losetup lsblk mount umount; do
		command -v "${tool}" >/dev/null || { echo "${tool} is required" >&2; exit 1; }
	done
	loop="$(losetup --find --show --partscan "${image}")"
	mountpoint="$(mktemp -d /tmp/sm3399mb-vendor.XXXXXX)"
	cleanup() {
		umount "${mountpoint}" 2>/dev/null || true
		rmdir "${mountpoint}" 2>/dev/null || true
		losetup -d "${loop}" 2>/dev/null || true
	}
	trap cleanup EXIT
	partition="$(lsblk -lnpo NAME,TYPE "${loop}" | awk '$2 == "part" { print $1; exit }')"
	source_device="${partition:-${loop}}"
	mount -o ro,noload "${source_device}" "${mountpoint}" 2>/dev/null || mount -o ro "${source_device}" "${mountpoint}"
	install -D -m 0644 "${mountpoint}/boot/armbianEnv.txt" "${out}/boot/armbianEnv.txt"
	for config in "${mountpoint}"/boot/config-*; do
		[[ -f "${config}" ]] && install -D -m 0644 "${config}" "${out}/boot/$(basename "${config}")"
	done
	fdt="$(sed -n 's/^fdtfile=//p' "${out}/boot/armbianEnv.txt" | head -n1)"
	fdt="$(basename "${fdt}")"
	chosen="$(find "${mountpoint}/boot" -type f -name "${fdt}" -print -quit)"
	if [[ -z "${chosen}" ]]; then chosen="$(find "${mountpoint}/boot" -type f -name '*3399*.dtb' -print -quit)"; fi
	if [[ -n "${chosen}" ]]; then install -m 0644 "${chosen}" "${out}/boot/dtb/rockchip/rk3399-sm3399mb.dtb"; fi
fi

if [[ -z "${chosen}" || ! -f "${out}/boot/dtb/rockchip/rk3399-sm3399mb.dtb" ]]; then
	echo "No SM3399MB DTB found under the vendor image" >&2
	exit 1
fi

image_hash="$(sha256sum "${image}" | awk '{print $1}')"
printf '%s\n' \
	"IMAGE=${image}" \
	"IMAGE_SHA256=${image_hash}" \
	"DTB=${chosen}" \
	> "${out}/manifest.txt"
echo "Vendor artifacts written to ${out}"
