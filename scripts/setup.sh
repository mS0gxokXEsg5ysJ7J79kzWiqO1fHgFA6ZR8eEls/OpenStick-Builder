#!/bin/sh -e
# OpenStick-Builder/scripts/setup.sh

# 启用非交互模式，避免构建过程卡在配置弹窗
DEBIAN_FRONTEND=noninteractive
DEBCONF_NONINTERACTIVE_SEEN=true

# 配置 dpkg 默认保留现有配置文件，加速静默安装
echo 'force-confdef' >> /etc/dpkg/dpkg.cfg
echo 'force-confold' >> /etc/dpkg/dpkg.cfg

# 预设时区（上海）与中文 UTF-8 语言环境
echo 'tzdata tzdata/Areas select Asia' | debconf-set-selections
echo 'tzdata tzdata/Zones/Asia select Shanghai' | debconf-set-selections
rm -f /etc/localtime /etc/timezone
echo "locales locales/default_environment_locale select zh_CN.UTF-8" | debconf-set-selections
echo "locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8, zh_CN.UTF-8 UTF-8" | debconf-set-selections
rm -f "/etc/locale.gen"

# 更新软件源并一次性安装基础网络、调制解调器、排障及内存优化组件
apt update -qqy
apt upgrade -qqy --with-new-pkgs
apt install -qqy --no-install-recommends \
	bc \
	iw \
	sudo \
	curl \
	wget \
	rmtfs \
	pcscd \
	tzdata \
	iperf3 \
	rfkill \
	vnstat \
	sqlite3 \
	libccid \
	locales \
	tcpdump \
	dnsmasq \
	hostapd \
	earlyoom \
	iproute2 \
	nftables \
	mtr-tiny \
	libc6-dev \
	zram-tools \
	qrtr-tools \
	libconfig11 \
	libqmi-utils \
	iputils-ping \
	libconfig-dev \
	wpasupplicant \
	openssh-server \
	bind9-dnsutils \
	linux-libc-dev \
	wireless-regdb \
	network-manager \
	ca-certificates \
	build-essential \
	wireguard-tools \
	bash-completion \
	systemd-timesyncd \
	netcat-traditional \
	mobile-broadband-provider-info

# 切换为上游签名的无线监管域数据库（匹配 6.12 内核内置证书，解决 country 00 验签失败）
update-alternatives --set regulatory.db /lib/firmware/regulatory.db-upstream || true

# 清理无用依赖、缓存、临时日志及机器唯一标识（确保刷机后重新生成）
apt autoremove -qqy
apt clean
update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 LANGUAGE=zh_CN:zh
cat <<EOF > /etc/default/locale
LANG=zh_CN.UTF-8
LC_ALL=zh_CN.UTF-8
LANGUAGE=zh_CN:zh
EOF
rm -rf /var/lib/apt/lists/*
rm -f /etc/machine-id
rm -f /var/lib/dbus/machine-id
rm -f /etc/ssh/ssh_host_*
find /var/log -type f -delete

# 解锁 root 账号并将默认密码设为 1
passwd -u root 2>/dev/null || true
echo "root:1" | chpasswd

# 允许 root 通过 SSH 密码登录，并关闭 DNS 反向解析与 GSSAPI（防止 WinSCP/SSH 认证卡顿）
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
mkdir -p /etc/ssh/sshd_config.d
cat <<EOF > /etc/ssh/sshd_config.d/99-allow-root.conf
PermitRootLogin yes
PasswordAuthentication yes
UseDNS no
GSSAPIAuthentication no
EOF

# 若未通过 configs/bashrc 预置，则保留默认逻辑；已预置则跳过覆盖
if [ ! -f /root/.bashrc ]; then
    cp -f /etc/skel/.bashrc /root/.bashrc 2>/dev/null || true
fi
chmod 644 /root/.bashrc

cat <<EOF >>/etc/bash.bashrc

alias ls='ls --color=auto -lh'
alias ll='ls --color=auto -lhA'
alias l='ls --color=auto -l'
alias cl='clear'
alias ip='ip --color'
alias bridge='bridge -color'
alias free='free -h'
alias df='df -h'
alias du='du -hs'

EOF

# 开启日志持久化落盘（便于排查异常重启，限制最大占用 16MB 保护 eMMC 空间）
mkdir -p /var/log/journal
cat <<EOF >> /etc/systemd/journald.conf
# 日志持久化保存在 /var/log/journal/
Storage=persistent
# 磁盘日志最大占用限制为 16MB
SystemMaxUse=16M
EOF

# 缩短 systemd 关机/重启等待服务停止的超时时间（从 90 秒降至 10 秒）
sed -i 's/^#\?DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=10s/' /etc/systemd/system.conf

# 启用 earlyoom 防内存耗尽假死，屏蔽后台 apt 自动更新避免突发吃内存
systemctl enable earlyoom || true
systemctl mask apt-daily.timer apt-daily-upgrade.timer || true

# 预装 VoCat（必须在修改 /etc/resolv.conf 之前执行，确保构建环境 DNS 正常）
curl -fsSL https://raw.githubusercontent.com/MengMengCode/VoCat/master/scripts/install.sh -o /tmp/vocat_install.sh
sed -i 's/systemctl enable --now/systemctl enable/g; s/systemctl start/true/g; s/systemctl restart/true/g; s/systemctl daemon-reload/true/g' /tmp/vocat_install.sh
# 临时模拟 systemd 运行目录，防止 chroot 环境下跳过生成 vocat.service
mkdir -p /run/systemd/system
bash /tmp/vocat_install.sh || true
rmdir /run/systemd/system 2>/dev/null || true
rm -f /tmp/vocat_install.sh
for svc in /etc/systemd/system/*vocat*.service /lib/systemd/system/*vocat*.service; do
    [ -f "$svc" ] && systemctl enable "$(basename "$svc")" || true
done
if [ ! -f /etc/systemd/system/vocat.service ] && [ ! -f /lib/systemd/system/vocat.service ]; then
    echo "ERROR: VoCat systemd 服务文件未生成！" >&2
    exit 1
fi

# 启用网络管理、DHCP/DNS（br0 网桥）、防火墙及读卡器服务
systemctl enable NetworkManager || true
systemctl enable dnsmasq
if [ -f /etc/nftables.conf ]; then
    sed -i 's/\biif "br0"/iifname "br0"/g; s/\boif "br0"/oifname "br0"/g; /redirect to :53/s/^/# /' /etc/nftables.conf
fi
systemctl enable nftables
systemctl enable pcscd.socket || true

# 彻底禁用所有 hostapd 开机自启（覆盖 systemd 主服务、模板服务及 SysV init 脚本），完整保留配置与程序便于日后随时启用
systemctl disable hostapd.service 'hostapd@*.service' 2>/dev/null || true
update-rc.d hostapd disable 2>/dev/null || true
rm -f /etc/systemd/system/multi-user.target.wants/hostapd*.service
rm -f /etc/systemd/system/network.target.wants/hostapd*.service

# 开机自动设置 Wi-Fi 监管域为 CN（完整支持 1~13 信道）
cat <<'EOF' > /etc/systemd/system/wifi-regdom.service
[Unit]
Description=开机设置 Wi-Fi 监管域为 CN
After=network-pre.target
Before=NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/sbin/iw reg set CN
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl enable wifi-regdom.service

# 开机自动唤醒 QMI 调制解调器进入在线模式（供 VoCat 直接调用）
cat <<'EOF' > /etc/systemd/system/modem-online.service
[Unit]
Description=Set QMI Modem Online at Boot
After=dev-wwan0qmi0.device
Wants=dev-wwan0qmi0.device

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 3
ExecStart=/usr/bin/qmicli -p -d /dev/wwan0qmi0 --dms-set-operating-mode=online
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl enable modem-online.service

# 启用基带远程文件系统与网络时间同步
systemctl enable rmtfs
systemctl enable systemd-timesyncd

# 启用 vnstat 流量统计并降低闪存写入频率（每 60 分钟落盘一次）
systemctl enable vnstat || true
sed -i 's/^;\?SaveInterval .*/SaveInterval 60/' /etc/vnstat.conf

# 屏蔽开机网络等待服务，加快启动速度
systemctl mask systemd-networkd-wait-online.service

# 忽略电源键事件，防止误触关机
sed -i 's/^#HandlePowerKey=poweroff/HandlePowerKey=ignore/' /etc/systemd/logind.conf

# 极限优化 ZRAM（适配 512MB 内存：zstd 高压缩率 + 100% 容量）
cat <<EOF > /etc/default/zramswap
ALGO=zstd       # 压缩算法：高压缩率（3.5~4倍），适合 512MB 极限省内存
PERCENT=100     # ZRAM 容量：物理 RAM 的 100%（约 512MB）
PRIORITY=100    # Swap 优先级：100（高于普通磁盘 Swap）
EOF

# 开启 IPv4 与 IPv6 内核路由转发
if [ -f /etc/sysctl.conf ]; then
    sed -i -e 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' -e 's/^#net.ipv6.conf.all.forwarding=1/net.ipv6.conf.all.forwarding=1/' /etc/sysctl.conf
    grep -q '^net.ipv4.ip_forward' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    grep -q '^net.ipv6.conf.all.forwarding' /etc/sysctl.conf || echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
else
    cat <<EOF > /etc/sysctl.conf
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
fi

# 内核内存极限调优、TCP BBR 拥塞控制与快速死链检测（防 4G/NAT 僵尸连接）
cat <<EOF >> /etc/sysctl.conf
# 关闭 Swap 预读，提升纯内存 ZRAM 读写效率
vm.page-cluster=0
# 积极将冷内存页压入 ZRAM（上限 200）
vm.swappiness=180
# 强制保留 16MB 应急物理内存，防止 Wi-Fi 驱动断流
vm.min_free_kbytes=16384
# 降低目录项与索引节点缓存回收倾向
vm.vfs_cache_pressure=50
# 启用 FQ 队列与 TCP BBR 拥塞控制
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
# 缩短 TCP Keepalive 检测周期（约 90 秒清除僵尸连接）
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_intvl=10
net.ipv4.tcp_keepalive_probes=3
EOF

# ========================== 固化 Wi-Fi 24/7 稳定性优化 ==========================
# 1. 写入 cfg80211 国家码模块参数与 NetworkManager 全局防随机 MAC 配置
mkdir -p /etc/modprobe.d /etc/NetworkManager/conf.d /etc/NetworkManager/system-connections
echo "options cfg80211 ieee80211_regdom=CN" > /etc/modprobe.d/cfg80211.conf
cat <<'EOF' > /etc/NetworkManager/conf.d/99-wifi-stable.conf
[device]
wifi.scan-rand-mac-address=no
EOF

# 2. 部署三级自愈 Wi-Fi 网关断流看门狗脚本与 systemd 定时器
cat <<'WATCHDOG' > /opt/wifi-watchdog.sh
#!/bin/bash
WLAN_IF="wlan0"
CONN_NAME="410-WiFi"
WIFI_DRIVER="wcn36xx"
FAIL_FILE="/tmp/wifi_fail_count"

# 若尚未配置目标 Wi-Fi 连接，直接退出防止首次开机误触发重启
nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "$CONN_NAME" || exit 0

GW=$(ip route show default dev "$WLAN_IF" | awk '{print $3}' | head -n 1)
if [ -n "$GW" ] && ping -c 3 -W 2 -I "$WLAN_IF" "$GW" >/dev/null 2>&1; then
    rm -f "$FAIL_FILE"
    exit 0
fi

FAILS=$(cat "$FAIL_FILE" 2>/dev/null || echo 0)
FAILS=$((FAILS + 1))
echo "$FAILS" > "$FAIL_FILE"

if [ "$FAILS" -le 2 ]; then
    logger -t wifi-watchdog "Gateway unreachable ($FAILS/3), reconnecting $CONN_NAME..."
    nmcli connection down "$CONN_NAME" >/dev/null 2>&1 || true
    sleep 2
    nmcli connection up "$CONN_NAME" >/dev/null 2>&1 || true
elif [ "$FAILS" -eq 3 ]; then
    logger -t wifi-watchdog "Reconnect failed 3 times, reloading $WIFI_DRIVER driver..."
    modprobe -r "$WIFI_DRIVER" >/dev/null 2>&1 || true
    sleep 2
    modprobe "$WIFI_DRIVER" >/dev/null 2>&1 || true
    sleep 3
    nmcli connection up "$CONN_NAME" >/dev/null 2>&1 || true
else
    logger -t wifi-watchdog "Driver reload failed, rebooting system..."
    rm -f "$FAIL_FILE"
    /sbin/reboot
fi
WATCHDOG
chmod +x /opt/wifi-watchdog.sh

cat <<'SVC' > /etc/systemd/system/wifi-watchdog.service
[Unit]
Description=WiFi Gateway Watchdog

[Service]
Type=oneshot
ExecStart=/opt/wifi-watchdog.sh
SVC

cat <<'TMR' > /etc/systemd/system/wifi-watchdog.timer
[Unit]
Description=Run WiFi Watchdog every 5min

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
TMR

systemctl enable wifi-watchdog.timer
# ==============================================================================

# 自动将 usb0 绑定到 br0 网桥（防止重启后 br0 处于 DOWN 导致 USB 无法 SSH）
mkdir -p /etc/udev/rules.d
cat <<'EOF' > /etc/udev/rules.d/99-usb0-bridge.rules
ACTION=="add", SUBSYSTEM=="net", KERNEL=="usb0", RUN+="/bin/sh -c 'for i in 1 2 3 4 5; do /sbin/ip link show br0 >/dev/null 2>&1 && break; sleep 1; done; /sbin/ip link set usb0 master br0; /sbin/ip link set usb0 up; /sbin/ip link set br0 up'"
EOF

# 设置默认 DNS（必须放在脚本末尾，避免影响 chroot 构建期联网）
rm -f /etc/resolv.conf
cat <<EOF > /etc/resolv.conf
nameserver 10.10.10.10
nameserver 1.1.1.1
nameserver 8.8.8.8
options timeout:2 attempts:3
EOF
