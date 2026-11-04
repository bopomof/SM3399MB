#!/usr/bin/env bash
set -euo pipefail

[[ "${1:-}" == trixie && "${3:-}" == orangepi-rk3399 && "${5:-}" == arm64 ]] || {
	echo "SM3399MB requires orangepi-rk3399 / Trixie / arm64" >&2
	exit 1
}

install -d /boot/overlay-user /etc/armbian
for overlay in /tmp/overlay/sm3399mb/*.dtbo; do
	[[ -f "${overlay}" ]] || continue
	install -m 0644 "${overlay}" "/boot/overlay-user/$(basename "${overlay}")"
done

[[ -f /boot/armbianEnv.txt ]] || {
	echo "Missing /boot/armbianEnv.txt" >&2
	exit 1
}

# The extracted vendor DTB is preferred because it contains the board's real
# GPIO, regulator, eMMC and display wiring. Never copy its rootdev setting.
fdtfile="rockchip/rk3399-orangepi.dtb"
if [[ -f /tmp/overlay/sm3399mb/rk3399-sm3399mb.dtb ]]; then
	install -D -m 0644 /tmp/overlay/sm3399mb/rk3399-sm3399mb.dtb \
		/boot/dtb/rockchip/rk3399-sm3399mb.dtb
	fdtfile="rockchip/rk3399-sm3399mb.dtb"
fi
sed -i '/^fdtfile=/d; /^user_overlays=/d' /boot/armbianEnv.txt
printf '%s\n' "fdtfile=${fdtfile}" 'user_overlays=sm3399mb-hardware' >> /boot/armbianEnv.txt

printf '%s\n' \
	'BOARD=sm3399mb' \
	'SOC=rk3399' \
	'CODENAME=trixie' \
	'DTB_SOURCE='"${fdtfile}" > /etc/armbian/sm3399mb-release
if [[ -f /tmp/overlay/sm3399mb/build-ref ]]; then
	install -m 0644 /tmp/overlay/sm3399mb/build-ref /etc/armbian/sm3399mb-build-ref
fi

# Keep the board identity available to diagnostics without changing the
# generated Armbian root UUID or first-boot account flow.
install -d /etc/modprobe.d
printf '%s\n' '# SM3399MB: USB WWAN modules are provided by the Armbian kernel.' \
	> /etc/modprobe.d/sm3399mb.conf
