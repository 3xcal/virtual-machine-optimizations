#!/usr/bin/env bash
# ==============================================================================
# Universal Ubuntu Cloud VM Raw Performance & Debloat Script (x86_64 & ARM64)
# Target: Minimal Idle RAM | Zero Swap | TCP BBR | No-Mitigations | Zero-Log
# Note: Run only AFTER initial cloud-init provisioning (SSH keys/network) is done.
# ==============================================================================

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

if [[ $EUID -ne 0 ]]; then
   echo "ERROR: Run this script as root (e.g., wget -qO- <URL> | sudo bash)"
   exit 1
fi

echo "[1/7] Removing Snapd & SquashFS loop mounts..."
if command -v snap >/dev/null 2>&1; then
  for pkg in $(snap list 2>/dev/null | awk 'NR>1 && $1 !~ /^(core|snapd|bare)/ {print $1}'); do
    snap remove --purge "$pkg" 2>/dev/null || true
  done
fi
systemctl disable --now snapd.service snapd.socket snapd.seeded.service 2>/dev/null || true
apt-get update -qq
apt-get purge -y snapd squashfs-tools 2>/dev/null || true
umount /snap/*/* 2>/dev/null || true
rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd ~/snap

echo "[2/7] Purging background daemons, Python watchers & hardware managers..."
systemctl disable --now \
  networkd-dispatcher rpcbind rpcbind.socket atd unattended-upgrades \
  multipathd modemmanager apport whoopsie avahi-daemon bolt systemd-oomd 2>/dev/null || true

apt-get purge -y \
  unattended-upgrades networkd-dispatcher rpcbind at multipath-tools \
  modemmanager apport whoopsie popularity-contest landscape-common \
  update-notifier bolt avahi-daemon plymouth accountsservice pollinate \
  fwupd udisks2 2>/dev/null || true

apt-get autoremove --purge -y
apt-get purge -y '?config-files' 2>/dev/null || true

echo "[3/7] Disabling background timers, unused TTYs, timesyncd & cloud-init..."
systemctl disable --now \
  apt-daily.timer apt-daily-upgrade.timer motd-news.timer \
  dpkg-db-backup.timer e2scrub_all.timer fstrim.timer systemd-timesyncd 2>/dev/null || true

systemctl stop \
  serial-getty@ttyS0.service getty@tty1.service \
  systemd-fsckd.service systemd-fsckd.socket 2>/dev/null || true

systemctl mask \
  serial-getty@ttyS0.service getty@tty1.service \
  systemd-fsckd.service systemd-fsckd.socket 2>/dev/null || true

mkdir -p /etc/cloud
touch /etc/cloud/cloud-init.disabled

echo "[4/7] Replacing systemd-resolved with static upstream DNS..."
systemctl disable --now systemd-resolved 2>/dev/null || true
rm -f /etc/resolv.conf
printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf

echo "[5/7] Configuring zero-RAM/zero-disk journald & cleaning caches..."
sed -i 's/^#*Storage=.*/Storage=none/' /etc/systemd/journald.conf
sed -i 's/^#*RuntimeMaxUse=.*/#RuntimeMaxUse=/' /etc/systemd/journald.conf
sed -i 's/^#*SystemMaxUse=.*/#SystemMaxUse=/' /etc/systemd/journald.conf
systemctl restart systemd-journald

apt-get clean
rm -rf /run/log/journal /var/log/journal/* /var/cache/apt/archives/* /var/log/*.gz /var/log/*.[0-9]

echo "[6/7] Applying zero-swap, TCP BBR, socket buffers & IPv6 disable..."
swapoff -a 2>/dev/null || true
sed -i '/swap/d' /etc/fstab

cat << 'EOF' > /etc/sysctl.d/99-raw-performance.conf
# Zero Swap & Aggressive Cache Retention
vm.swappiness = 0
vm.vfs_cache_pressure = 50
vm.dirty_background_ratio = 10
vm.dirty_ratio = 30

# Network Throughput (BBR + Socket Buffers)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.netdev_max_backlog = 5000

# Enable IPv4 Packet Forwarding
net.ipv4.ip_forward = 1

# Disable IPv6 Stack Overhead
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

sysctl --system >/dev/null

echo "[7/7] Tuning GRUB (mitigations=off), root fstab (noatime), I/O scheduler & dpkg nodoc..."
if [[ -d /etc/default/grub.d ]]; then
  echo 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT mitigations=off"' > /etc/default/grub.d/99-mitigations-off.cfg
  update-grub 2>/dev/null || true
elif [[ -f /etc/default/grub ]] && ! grep -q "mitigations=off" /etc/default/grub; then
  sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 mitigations=off"/' /etc/default/grub
  update-grub 2>/dev/null || true
fi

awk '!/^#/ && $2 == "/" {
  if ($4 !~ /(^|,)noatime(,|$)/)    $4 = $4 ",noatime"
  if ($4 !~ /(^|,)nodiratime(,|$)/) $4 = $4 ",nodiratime"
} 1' /etc/fstab > /etc/fstab.tmp && mv /etc/fstab.tmp /etc/fstab
mount -o remount / 2>/dev/null || true

echo 'ACTION=="add|change", KERNEL=="sd[a-z]|vd[a-z]|nvme[0-9]*", ATTR{queue/scheduler}="none"' > /etc/udev/rules.d/60-io-scheduler.rules
udevadm control --reload-rules && udevadm trigger

cat << 'EOF' > /etc/dpkg/dpkg.cfg.d/01_nodoc
path-exclude=/usr/share/doc/*
path-exclude=/usr/share/man/*
path-exclude=/usr/share/info/*
EOF

echo "=============================================================================="
echo "Optimization complete! Rebooting in 5 seconds to apply kernel/GRUB changes..."
echo "=============================================================================="
sleep 5
reboot