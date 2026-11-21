#!/bin/sh -e

CHROOT=${CHROOT=$(pwd)/rootfs}
RELEASE=${RELEASE=stable}
HOST_NAME=${HOST_NAME=openstick}

rm -rf ${CHROOT}

# Use mmdebstrap for faster builds (god, it's so much faster)
echo "Using mmdebstrap for fast bootstrap..."
mmdebstrap --arch=arm64 \
    --include=systemd,udev,dbus,apt,wget,ca-certificates \
    --keyring=/usr/share/keyrings/debian-archive-keyring.gpg \
    ${RELEASE} ${CHROOT}

cat << EOF > ${CHROOT}/etc/apt/sources.list
deb http://deb.debian.org/debian ${RELEASE} main contrib non-free-firmware
deb http://deb.debian.org/debian-security/ ${RELEASE}-security main contrib non-free-firmware
deb http://deb.debian.org/debian ${RELEASE}-updates main contrib non-free-firmware
EOF

# Speed up apt
cat << EOF > ${CHROOT}/etc/apt/apt.conf.d/99speedup
APT::Acquire::Retries "3";
APT::Acquire::http::Timeout "10";
APT::Acquire::ftp::Timeout "10";
Acquire::Languages "none";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
DPkg::Options::="--force-confdef";
DPkg::Options::="--force-confold";
EOF

mount -t proc proc ${CHROOT}/proc/
mount -t sysfs sys ${CHROOT}/sys/
mount -o bind /dev/ ${CHROOT}/dev/
mount -o bind /dev/pts/ ${CHROOT}/dev/pts/
mount -o bind /run ${CHROOT}/run/

# configs'n stuff
mkdir -p ${CHROOT}/etc/systemd/system
cp -a configs/system/* ${CHROOT}/etc/systemd/system
cp configs/nftables.conf ${CHROOT}/etc/nftables.conf
mkdir -p ${CHROOT}/etc/NetworkManager/system-connections
mkdir -p ${CHROOT}/etc/NetworkManager/conf.d
cp configs/*.nmconnection ${CHROOT}/etc/NetworkManager/system-connections
chmod 0600 ${CHROOT}/etc/NetworkManager/system-connections/*
cp configs/99-custom.conf ${CHROOT}/etc/NetworkManager/conf.d/

# chroot setup
cp configs/install_dnsproxy.sh ${CHROOT}
cp scripts/setup.sh ${CHROOT}

# Copy qemu static and run setup script in chroot
cp /usr/bin/qemu-aarch64-static ${CHROOT}/usr/bin/
chroot ${CHROOT} qemu-aarch64-static /bin/sh -c "/setup.sh"

# cleanup
for a in proc sys dev/pts dev run; do
    umount ${CHROOT}/${a}
done;

rm ${CHROOT}/install_dnsproxy.sh
rm -f ${CHROOT}/setup.sh
rm -f ${CHROOT}/usr/bin/qemu-aarch64-static
echo -n > ${CHROOT}/root/.bash_history

echo ${HOST_NAME} > ${CHROOT}/etc/hostname
sed -i "/localhost/ s/$/ ${HOST_NAME}/" ${CHROOT}/etc/hosts

# setup dnsmasq
cp -a configs/dhcp.conf ${CHROOT}/etc/dnsmasq.d/dhcp.conf

# hosts entry for the LAN IP
cat <<EOF >> ${CHROOT}/etc/hosts

192.168.100.1	${HOST_NAME}
EOF

# add rc-local
cp -a configs/rc.local ${CHROOT}/etc/rc.local
chmod +x ${CHROOT}/etc/rc.local

# add MSM8916 USB gadget
cp -a configs/msm8916-usb-gadget.sh ${CHROOT}/usr/sbin/
cp configs/msm8916-usb-gadget.conf ${CHROOT}/etc/

# setup WiFi AP with hostapd
mkdir -p ${CHROOT}/etc/hostapd
cp configs/hostapd.conf ${CHROOT}/etc/hostapd/
cp configs/wifi-ap.sh ${CHROOT}/usr/sbin/
chmod +x ${CHROOT}/usr/sbin/wifi-ap.sh

cp -a scripts/msm-firmware-loader.sh ${CHROOT}/usr/sbin

# install kernel (支持手动传入 KERNEL_URL，否则自动从 GitHub Releases/Pre-release 拉取最新 .apk)
KERNEL_REPO="mS0gxokXEsg5ysJ7J79kzWiqO1fHgFA6ZR8eEls/OpenStick-Kernel-Compiler"
if [ -z "${KERNEL_URL}" ]; then
    KERNEL_URL=$(curl -sSL "https://api.github.com/repos/${KERNEL_REPO}/releases?per_page=5" \
        | grep -oE 'https://github\.com/[^"]+\.apk' | head -n 1)
fi
if [ -z "${KERNEL_URL}" ]; then
    echo "ERROR: 未找到可用的远程内核 .apk 链接" >&2
    exit 1
fi
echo "Downloading kernel: ${KERNEL_URL}"
curl -fsSL "${KERNEL_URL}" -o /tmp/kernel.apk
tar xzf /tmp/kernel.apk -C ${CHROOT} --exclude=.PKGINFO --exclude=.SIGN* 2>/dev/null
rm -f /tmp/kernel.apk

# 动态获取解压后的内核模块目录名并生成 modules.dep
KVER=$(ls -1 ${CHROOT}/usr/lib/modules/ | head -n 1)
if [ -n "${KVER}" ]; then
    depmod -b ${CHROOT} "${KVER}"
fi

mkdir -p ${CHROOT}/boot/extlinux
cp configs/extlinux.conf ${CHROOT}/boot/extlinux

# copy custom dtb's
cp dtbs/* ${CHROOT}/boot/dtbs/qcom/

# create missing directory
mkdir -p ${CHROOT}/lib/firmware/msm-firmware-loader

# update fstab
echo "PARTUUID=80780b1d-0fe1-27d3-23e4-9244e62f8c46\t/boot\text2\tdefaults\t0 2" > ${CHROOT}/etc/fstab

# backup rootfs
tar cpzf rootfs.tgz --exclude="usr/bin/qemu-aarch64-static" -C rootfs .
