#!/usr/bin/env bash
set -euo pipefail

if (( EUID == 0 )); then
	printf '%s\n' \
		'Run this build as your normal user, not with sudo.' \
		'Validate sudo first with: sudo -v' >&2
	exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/.armbian-build}"
ARMBIAN_REF="${ARMBIAN_REF:-813ae7cf3ccd40df1d287733e1838ed0812ceeb8}"
DEFAULT_VENDOR_IMAGE="${ROOT_DIR}/Armbian_21.08.1_sm3399mb_focal_current_5.10.60.img"
VENDOR_IMAGE="${VENDOR_IMAGE:-${DEFAULT_VENDOR_IMAGE}}"
VENDOR_DTB="${VENDOR_DTB:-}"
PREPARE_ONLY=no
COMPILE_ARGS=()

usage() {
	cat >&2 <<'EOF'
Usage: scripts/build-armbian-trixie.sh [options] [Armbian compile options]

Options:
  --vendor-image FILE  Extract the SM3399MB DTB from an original image
  --vendor-dtb FILE    Use a DTB directly instead of extracting an image
  --prepare-only       Clone and stage Armbian files without compiling
  -h, --help           Show this help

The default vendor image is the path supplied for this board. Override it with
VENDOR_IMAGE=... or pass --vendor-image. If it is absent, the script prepares
a mainline Orange Pi RK3399 based image and reports that real board DTB validation is
still required.
EOF
}
while (($#)); do
	case "$1" in
		--vendor-image) [[ $# -ge 2 ]] || { usage; exit 2; }; VENDOR_IMAGE="$2"; shift 2 ;;
		--vendor-dtb) [[ $# -ge 2 ]] || { usage; exit 2; }; VENDOR_DTB="$2"; shift 2 ;;
		--prepare-only) PREPARE_ONLY=yes; shift ;;
		-h|--help) usage; exit 0 ;;
		*) COMPILE_ARGS+=("$1"); shift ;;
	esac
done

command -v git >/dev/null || { echo "git is required" >&2; exit 1; }
command -v dtc >/dev/null || { echo "Install device-tree-compiler first" >&2; exit 1; }
[[ -x "${ROOT_DIR}/scripts/extract-vendor-image.sh" ]] || {
	echo "Missing scripts/extract-vendor-image.sh" >&2; exit 1;
}

# Armbian's tag lookup is too aggressive for slow links. These are process
# local and do not alter the user's global Git configuration.
export GIT_HTTP_LOW_SPEED_LIMIT="${GIT_HTTP_LOW_SPEED_LIMIT:-1}"
export GIT_HTTP_LOW_SPEED_TIME="${GIT_HTTP_LOW_SPEED_TIME:-180}"
git_config_count="${GIT_CONFIG_COUNT:-0}"
[[ "${git_config_count}" =~ ^(0|[1-9][0-9]*)$ ]] || {
	echo "GIT_CONFIG_COUNT must be a non-negative integer" >&2; exit 1;
}
export "GIT_CONFIG_KEY_${git_config_count}=http.version"
export "GIT_CONFIG_VALUE_${git_config_count}=HTTP/1.1"
export GIT_CONFIG_COUNT="$((git_config_count + 1))"

if [[ ! -d "${BUILD_DIR}" ]]; then
	git clone https://github.com/armbian/build.git "${BUILD_DIR}"
fi
[[ -d "${BUILD_DIR}/.git" ]] || { echo "BUILD_DIR is not an Armbian checkout" >&2; exit 1; }

docker_patch="${ROOT_DIR}/armbian/skip-missing-docker.patch"
if git -C "${BUILD_DIR}" apply --reverse --check "${docker_patch}" >/dev/null 2>&1; then
	git -C "${BUILD_DIR}" apply --reverse "${docker_patch}"
fi
if [[ -n "$(git -C "${BUILD_DIR}" status --porcelain --untracked-files=no)" ]]; then
	echo "Armbian checkout has tracked changes; use a dedicated BUILD_DIR" >&2
	exit 1
fi
if ! git -C "${BUILD_DIR}" cat-file -e "${ARMBIAN_REF}^{commit}" 2>/dev/null; then
	git -C "${BUILD_DIR}" fetch --depth 1 origin "${ARMBIAN_REF}"
fi
git -C "${BUILD_DIR}" checkout --detach "${ARMBIAN_REF}"
git -C "${BUILD_DIR}" apply "${docker_patch}"

patches="${BUILD_DIR}/userpatches"
mkdir -p "${patches}/extensions" "${patches}/overlay/sm3399mb"
for destination in "${patches}/customize-image.sh" "${patches}/extensions/sm3399mb.sh"; do
	if [[ -e "${destination}" ]] && ! cmp -s "${destination}" \
		"${ROOT_DIR}/armbian/$(basename "${destination}")"; then
		echo "Refusing to replace existing customization: ${destination}" >&2
		exit 1
	fi
done
cp "${ROOT_DIR}/armbian/sm3399mb.sh" "${patches}/extensions/sm3399mb.sh"
cp "${ROOT_DIR}/armbian/customize-image.sh" "${patches}/customize-image.sh"

for source in "${ROOT_DIR}/dts/overlays/"*.dts; do
	overlay="$(basename "${source}" .dts)"
	dtc -@ -I dts -O dtb -o "${patches}/overlay/sm3399mb/${overlay}.dtbo" "${source}"
done

vendor_dir="${ROOT_DIR}/vendor"
if [[ -n "${VENDOR_DTB}" ]]; then
	[[ -f "${VENDOR_DTB}" ]] || { echo "Vendor DTB not found: ${VENDOR_DTB}" >&2; exit 1; }
	rm -rf "${vendor_dir}"
	install -d "${vendor_dir}/boot/dtb/rockchip"
	install -m 0644 "${VENDOR_DTB}" "${vendor_dir}/boot/dtb/rockchip/rk3399-sm3399mb.dtb"
	printf '%s\n' "DIRECT_DTB=${VENDOR_DTB}" > "${vendor_dir}/manifest.txt"
elif [[ -f "${VENDOR_IMAGE}" ]]; then
	"${ROOT_DIR}/scripts/extract-vendor-image.sh" "${VENDOR_IMAGE}" "${vendor_dir}"
else
	echo "Vendor image not found: ${VENDOR_IMAGE}" >&2
	echo "Continuing with the mainline Orange Pi RK3399 DTB; provide the image before hardware testing." >&2
	rm -rf "${vendor_dir}"
	install -d "${vendor_dir}"
	printf '%s\n' "DTB=missing" "IMAGE=${VENDOR_IMAGE}" > "${vendor_dir}/manifest.txt"
fi
if [[ -f "${vendor_dir}/boot/dtb/rockchip/rk3399-sm3399mb.dtb" ]]; then
	cp "${vendor_dir}/boot/dtb/rockchip/rk3399-sm3399mb.dtb" \
		"${patches}/overlay/sm3399mb/rk3399-sm3399mb.dtb"
fi
if [[ -f "${vendor_dir}/manifest.txt" ]]; then
	cp "${vendor_dir}/manifest.txt" "${patches}/overlay/sm3399mb/vendor-manifest.txt"
fi
printf '%s\n' "${ARMBIAN_REF}" > "${patches}/overlay/sm3399mb/build-ref"

if [[ "${PREPARE_ONLY}" == yes ]]; then
	echo "Prepared ${BUILD_DIR}; vendor artifacts: ${vendor_dir}"
	exit 0
fi

cd "${BUILD_DIR}"
./compile.sh build BOARD=orangepi-rk3399 BRANCH=current RELEASE=trixie \
	BUILD_MINIMAL=no BUILD_DESKTOP=no KERNEL_CONFIGURE=no EXPERT=yes \
	ENABLE_EXTENSIONS=sm3399mb COMPRESS_OUTPUTIMAGE=sha,xz PREFER_DOCKER=no \
	"${COMPILE_ARGS[@]}"
echo "Image output: ${BUILD_DIR}/output/images/"
