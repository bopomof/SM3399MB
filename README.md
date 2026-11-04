# SM3399MB Armbian Trixie 构建套件

本目录提供 SM3399MB（Rockchip RK3399）的 Armbian Debian Trixie 构建脚本。构建基于 Armbian 官方维护的 `orangepi-rk3399` RK3399 启动链和 `current` 内核，补充 RK3399 常用的串口、网卡、看门狗、MPTCP 与 USB 蜂窝模块配置。

SM3399MB 的实际 GPIO、电源、eMMC、Wi-Fi、显示和外设连接必须以该板原厂镜像中的 DTB 为准。脚本会优先提取并安装原厂 DTB；它不会把 Ubuntu Focal 根文件系统或旧内核复制到 Trixie 镜像中。

## 当前状态

用户提供的原厂镜像路径是：

```text
/dev/shm/Armbian_21.08.1_sm3399mb_focal_current_5.10.60/Armbian_21.08.1_sm3399mb_focal_current_5.10.60.img
```

原厂镜像已经放在项目根目录，脚本会提取其中的 `boot/sm3399b.dtb`；该文件内部模型是 `LJL SM3399MB`。如果镜像不存在，脚本会回退到主线 Orange Pi RK3399 DTB，这只能用于构建流程验证，不能视为已经完成 SM3399MB 真机适配。

参考资料和实现依据：

- `YS-A99-Board` 的 Trixie 构建脚本、Armbian 扩展和设备树 overlay 组织方式。
- `rk33xx-armbian` 中的 RK3399 板型、Armbian 构建入口及 `sm3399b` 设备树登记。
- `amlogic-s9xxx-armbian` 中的 Rockchip 镜像布局和设备文件管理经验。

## 准备依赖

在 Debian/Ubuntu amd64 主机上安装 Git、设备树编译器和 Armbian 构建需要的基本工具。完整构建需要可用的 `sudo`、网络和约 60 GiB 空闲空间。

```bash
sudo apt update
sudo apt install git device-tree-compiler util-linux xz-utils
sudo -v
```

构建入口必须由普通用户运行，不要使用 `sudo ./scripts/build-armbian-trixie.sh`。

## 构建

如果原厂镜像位于用户给出的默认路径：

```bash
cd /home/tim/work/SM3399MB
./scripts/build-armbian-trixie.sh
```

也可以显式指定镜像或直接指定 DTB：

```bash
./scripts/build-armbian-trixie.sh --vendor-image /path/to/SM3399MB-original.img
./scripts/build-armbian-trixie.sh --vendor-dtb /path/to/rk3399-sm3399mb.dtb
```

只准备 Armbian 源码、设备树 overlay 和原厂文件，不开始耗时的内核/rootfs 构建：

```bash
./scripts/build-armbian-trixie.sh --prepare-only
```

输出位于 `.armbian-build/output/images/`，通常包括 `.img.xz`、校验文件和构建日志。构建提交可通过 `ARMBIAN_REF` 覆盖，源码目录可通过 `BUILD_DIR` 覆盖。

## 原厂镜像提取

提取工具优先使用 `7z` 直接读取镜像中的 ext4 分区，不需要 root；没有 `7z` 时才回退到只读 loop 挂载。它会保存 `/boot` 中的 DTB、`armbianEnv.txt`、内核配置和版本信息到 `vendor/`：

```bash
./scripts/extract-vendor-image.sh /path/to/SM3399MB-original.img
cat vendor/manifest.txt
```

构建时，提取的 DTB 会安装成 `/boot/dtb/rockchip/rk3399-sm3399mb.dtb`，并设置：

```ini
fdtfile=rockchip/rk3399-sm3399mb.dtb
user_overlays=sm3399mb-hardware
```

如果没有 DTB，才回退到 Armbian 的 Orange Pi RK3399 DTB。`sm3399mb-hardware` overlay 只写入板名和兼容字符串，不猜测 GPIO；电气差异应从原厂 DTB 或经过验证的后续 overlay 中补充。

## 写入 SD 卡

确认目标是 SD 卡整盘设备后执行。此操作会覆盖目标盘，脚本拒绝常见的系统盘 `/dev/sda` 和 `/dev/nvme0n1`：

```bash
lsblk -d -o NAME,SIZE,MODEL,TYPE
sudo ./scripts/flash-sd.sh .armbian-build/output/images/Armbian_*.img.xz /dev/sdX
```

首次启动建议保留原厂 eMMC，使用串口记录 U-Boot 和内核日志。确认 SD 卡稳定后再使用 Armbian 的安装工具处理 eMMC；不要根据 `mmcblk0`/`mmcblk1` 编号猜测目标。

## 已安装系统更新 overlay

在本项目构建的内核上，可以把 overlay 安装到现有 Armbian 系统：

```bash
sudo ./scripts/install-sm3399mb.sh
```

如果要安装单独提取的 DTB：

```bash
sudo ./scripts/install-sm3399mb.sh /path/to/rk3399-sm3399mb.dtb
```

脚本会备份 `/boot/armbianEnv.txt`，并要求当前内核包含 `CONFIG_GPIO_WATCHDOG=y`。重启后检查：

```bash
cat /etc/armbian/sm3399mb-release
cat /proc/device-tree/model; echo
uname -a
grep -E 'GPIO_WATCHDOG|MPTCP|USB_NET_QMI_WWAN|SERIAL_8250_DW' /boot/config-$(uname -r)
```

## 适配边界

原厂 DTB 已经提取，但以下项目仍必须在 SM3399MB 实机上确认：DDR/U-Boot 启动、eMMC 和 SD 卡、以太网 PHY、USB 供电、PCIe、Wi-Fi/蓝牙、显示、音频、硬件 watchdog、串口电平和 4G 模块。`rk3399-sm3399b.dtb`（`rk33xx-armbian` 中的另一块板）不能代替本项目从原厂镜像提取的 `sm3399b.dtb`；两个型号同属 RK3399，但管脚和电源连接需要原厂资料或实测确认。
