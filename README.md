# OpenStick 镜像构建工具（Image Builder）

用于基于 Qualcomm MSM8916 芯片的 4G 上网棒的系统镜像构建工具。

本构建工具使用由 [postmarketOS](https://postmarketos.org/) 提供的 MSM8916 设备预编译内核：[linux-postmarketos-qcom-msm8916](https://pkgs.postmarketos.org/package/master/postmarketos/aarch64/linux-postmarketos-qcom-msm8916)。

> [!NOTE]
> **分支说明：**
> - `debian`：基于 Debian（稳定版）的系统镜像分支（默认分支）。
> - `ubuntu-24.04`：基于 Ubuntu 24.04 LTS（Noble）的系统镜像分支，构建步骤完全相同。
> - Alpine（上游版本）：请参考[原始仓库的 Alpine 分支](https://github.com/kinsamanka/OpenStick-Builder/tree/alpine)，该分支不再维护。

## 构建说明

### 本地构建

已测试并确认可以在以下系统上正常构建：

- Ubuntu 22.04
- Ubuntu 24.04
- Ubuntu 25.04

**克隆仓库**

```shell
git clone --recurse-submodules https://github.com/mS0gxokXEsg5ysJ7J79kzWiqO1fHgFA6ZR8eEls/OpenStick-Builder.git
cd OpenStick-Builder/
```

### 快速构建（Debian 分支）

```shell
git checkout debian
sudo ./build.sh
```

### 快速构建（Ubuntu 24.04 分支）

```shell
git checkout ubuntu-24.04
sudo ./build.sh
```

### 详细构建步骤（适用于所有分支）

**1. 安装依赖**

```shell
sudo scripts/install_deps.sh
```

**2. 构建 HYP 和 LK2ND**

这些自定义引导加载程序（Bootloader）提供了对 `extlinux.conf` 配置文件的基本支持，类似于 U-Boot 和 Depthcharge。

```shell
sudo scripts/build_hyp_aboot.sh
```

**3. 提取 Qualcomm 固件**

提取原始引导加载程序（Bootloader），并创建新的分区表，使其能够充分利用整个 eMMC 存储空间。

```shell
sudo scripts/extract_fw.sh
```

**4. 使用 debootstrap 创建根文件系统（RootFS）**

```shell
sudo scripts/debootstrap.sh
```

**5. 构建 gadget-tools（USB 网络及设备工具）**

```shell
sudo scripts/build_gt.sh
```

**6. 创建系统镜像**

```shell
sudo scripts/build_images.sh
```

生成的固件文件将保存在 `files` 目录中。

### 使用 GitHub Actions 云端构建

1. Fork（派生）此仓库。
2. 运行 [Build 构建工作流](../../actions/workflows/build.yml)。
   - 点击 **Run workflow（运行工作流）**。
   - 等待工作流执行完成。
   - 点击工作流摘要页面，然后下载生成的构建产物（Artifact）。

## 自定义配置

编辑 [`scripts/setup.sh`](scripts/setup.sh)，即可添加或删除系统软件包。

注意：该脚本是在 `chroot` 环境内部执行的。

## 固件安装

> [!WARNING]
> 以下操作可能导致设备变砖，使设备无法启动。请谨慎操作，并自行承担风险！

> [!IMPORTANT]
> **务必先备份原始固件：**
>
> ```shell
> edl rf orig_fw.bin
> ```

### 前置条件

需要准备：

- [EDL 工具](https://github.com/bkerler/edl)
- Android Fastboot 工具

安装 Fastboot：

```shell
sudo apt install fastboot
```

### 安装步骤

**1. 确保设备正在运行原厂固件（Stock Firmware）。**

**2. 进入 Qualcomm EDL 模式。**

参考此[操作指南](https://wiki.postmarketos.org/wiki/Zhihe_series_LTE_dongles_(generic-zhihe)#How_to_enter_flash_mode)。

**3. 备份必要分区。**

需要从原厂固件中备份以下文件：

- `fsc.bin`
- `fsg.bin`
- `modem.bin`
- `modemst1.bin`
- `modemst2.bin`
- `persist.bin`
- `sec.bin`

如果这些文件已经存在，可以跳过此步骤。

```shell
for n in fsc fsg modem modemst1 modemst2 persist sec; do
    edl r ${n} ${n}.bin
done
```

**4. 安装 aboot 引导加载程序。**

```shell
edl w aboot aboot.mbn
```

**5. 重启进入 Fastboot 模式。**

```shell
edl e boot
edl reset
```

**6. 刷写固件。**

```shell
fastboot flash partition gpt_both0.bin
fastboot flash aboot aboot.mbn
fastboot flash hyp hyp.mbn
fastboot flash rpm rpm.mbn
fastboot flash sbl1 sbl1.mbn
fastboot flash tz tz.mbn
fastboot flash boot boot.bin
fastboot flash rootfs rootfs.bin
```

**7. 恢复原始分区。**

```shell
for n in fsc fsg modem modemst1 modemst2 persist sec; do
    fastboot flash ${n} ${n}.bin
done
```

**8. 重启设备。**

```shell
fastboot reboot
```

## 安装后配置（Post-Install）

### 1. 网络配置

默认网络参数如下：

| 配置项 | 默认值 |
|---|---|
| Wi-Fi 名称（SSID） | `4G-UFI-XX` |
| Wi-Fi 密码 | `1234567890` |
| 设备 IP 地址 | `192.168.168.1` |

### 2. 默认用户

| 配置项 | 默认值 |
|---|---|
| 用户名 | `root` |
| 密码 | `1` |

### 3. 修改设备树（DTB）

如果你的设备不是基于 **UFI003** 的主板，需要修改 `/boot/extlinux/extlinux.conf`，使用与实际硬件相匹配的设备树文件。

执行以下命令：

```shell
sed -i 's/ufi003_mb_v02/<BOARD>/' /boot/extlinux/extlinux.conf
```

其中 `<BOARD>` 应替换为对应的主板设备树名称：

| 主板型号 | 对应设备树名称 |
|---|---|
| UFI003 | `ufi003_mb_v02` |
| UF896 | `thwc-uf896` |
| UFIxxx | `thwc-ufi001c` |
| JZxxx | `jz01-45-v33` |
| MF800 | `fy-mf800` |

### 4. 更新 Debian 镜像的内核

从以下地址获取内核下载链接：

http://mirror.postmarketos.org/postmarketos/master/aarch64/

示例：下载并安装 `6.12.1-r7` 版本的 MSM8916 内核。

```shell
wget -O - http://mirror.postmarketos.org/postmarketos/master/aarch64/linux-postmarketos-qcom-msm8916-6.12.1-r7.apk \
        | tar xkzf - -C / --exclude=.PKGINFO --exclude='.SIGN*' 2>/dev/null
```

该命令会将内核 APK 包中的文件解压到系统根目录 `/`，并排除软件包元数据和签名文件。
