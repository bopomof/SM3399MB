#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(id -u)" -eq 0 ]] || { echo "Run as root: sudo $0" >&2; exit 1; }
command -v dtc >/dev/null || { echo "Install device-tree-compiler first" >&2; exit 1; }
config="/boot/config-$(uname -r)"
grep -q '^CONFIG_GPIO_WATCHDOG=y$' "${config}" || {
	echo "This kernel lacks CONFIG_GPIO_WATCHDOG=y; install the SM3399MB kernel first." >&2
	exit 1
}
[[ -f /boot/armbianEnv.txt ]] || { echo "Missing /boot/armbianEnv.txt" >&2; exit 1; }
cp -a /boot/armbianEnv.txt "/boot/armbianEnv.txt.backup-$(date +%Y%m%d%H%M%S)"
install -d /boot/overlay-user
for source in "${ROOT_DIR}/dts/overlays/"*.dts; do
	name="$(basename "${source}" .dts)"
	dtc -@ -I dts -O dtb -o "/boot/overlay-user/${name}.dtbo" "${source}"
done

if [[ -f "${1:-}" ]]; then
	install -D -m 0644 "$1" /boot/dtb/rockchip/rk3399-sm3399mb.dtb
	sed -i '/^fdtfile=/d' /boot/armbianEnv.txt
	printf '%s\n' 'fdtfile=rockchip/rk3399-sm3399mb.dtb' >> /boot/armbianEnv.txt
fi
existing="$(sed -n 's/^user_overlays=//p' /boot/armbianEnv.txt | head -n1)"
read -r -a overlays <<< "${existing}"
ordered=(sm3399mb-hardware)
for overlay in "${overlays[@]}"; do
	[[ "${overlay}" == sm3399mb-hardware || -z "${overlay}" ]] || ordered+=("${overlay}")
done
sed -i '/^user_overlays=/d' /boot/armbianEnv.txt
printf 'user_overlays=%s\n' "${ordered[*]}" >> /boot/armbianEnv.txt
echo "SM3399MB DT overlays installed; reboot to apply them."
