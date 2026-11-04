#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 2 ]] || { echo "Usage: sudo $0 <image.img|image.img.xz> <disk>" >&2; exit 2; }
image="$1"
target="$2"
[[ -f "${image}" ]] || { echo "Image not found: ${image}" >&2; exit 1; }
[[ -b "${target}" ]] || { echo "Target is not a block device: ${target}" >&2; exit 1; }
(( EUID == 0 )) || { echo "Run as root: sudo $0 ..." >&2; exit 1; }
[[ "${target}" != /dev/nvme0n1 && "${target}" != /dev/sda ]] || {
	echo "Refusing likely system disk ${target}; choose a removable disk explicitly." >&2
	exit 1
}
for partition in "${target}"*; do
	[[ "${partition}" == "${target}" || ! -b "${partition}" ]] || \
		umount "${partition}" 2>/dev/null || true
done
case "${image}" in
	*.xz) xzcat -- "${image}" | dd of="${target}" bs=4M status=progress conv=fsync oflag=direct ;;
	*) dd if="${image}" of="${target}" bs=4M status=progress conv=fsync oflag=direct ;;
esac
sync
echo "Flashed ${image} to ${target}; remove the card only after sync completes."
