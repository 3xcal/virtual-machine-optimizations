#!/usr/bin/env bash
# ==============================================================================
# Oracle Cloud Infrastructure (OCI) - Ubuntu E2.1.Micro / ARM Raw Optimization
# Target: ~80 MB Idle RAM | Zero Swap | BBR | No-Mitigations | Zero-Log Overhead
# Note: Preserves iscsid (required for OCI root boot volume).
# ==============================================================================

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

if [[ $EUID -ne 0 ]]; then
   echo "ERROR: Run this script as root (e.g., curl -fsSL <URL> | sudo bash)"
   exit 1
fi

echo "[1/8] Removing Snapd & Oracle Cloud Agent..."
snap remove oracle-cloud-agent 2>/dev/null || true
systemctl disable --now snapd.service snapd.socket snapd.seeded.service oracle-cloud-agent oracle-cloud-agent-updater 2>/dev/null || true
apt-get update -qq
apt-get purge -y snapd squashfs-tools oracle-cloud-agent oracle-cloud-agent-updater 2>/dev/null || true
rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd ~/snap /var/lib/oracle-cloud-agent

echo "[2/8] Purging background daemons, Python watchers & hardware managers..."
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

echo "[3/8] Disabling background timers, TTY consoles, timesyncd & cloud-init..."
systemctl disable --now \
  apt-daily.timer apt-daily-upgrade.timer motd-news.timer \
  dpkg-db-backup.timer e2scrub_all.timer fstrim.timer systemd-timesyncd 2>/dev/null || true

systemctl stop \
  serial-getty@ttyS0.service getty@tty1.service \
  systemd-fsckd.service systemd-fsckd.socket 2>/dev/null || true

systemctl mask \
  serial-getty@ttyS0.service getty@tty1.service \
  systemd-fsckd.service systemd-fsckd.socket 2>/dev/null || true

touch /etc/cloud/cloud-init.disabled

echo "[4/8] Replacing systemd-resolved with static upstream DNS..."
systemctl disable --now systemd-resolved 2>/dev/null || true
rm -f /etc/resolv.conf
printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf

echo "[5/8] Configuring zero-RAM/zero-disk journald & cleaning caches..."
sed -i 's/^#*Storage=.*/Storage=none/' /etc/systemd/journald.conf
sed -i 's/^#*RuntimeMaxUse=.*/#RuntimeMaxUse=/' /etc/systemd/journald.conf
sed -i 's/^#*SystemMaxUse=.*/#SystemMaxUse=/' /etc/systemd/journald.conf
systemctl restart systemd-journald

apt-get clean
rm -rf /run/log/journal /var/log/journal/* /var/cache/apt/archives/* /var/log/*.gz /var/log/*.[0-9]

echo "[6/8] Applying zero-swap, TCP BBR, socket buffers & IPv6 disable..."
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

echo "[7/8] Tuning GRUB (mitigations=off), fstab (noatime), I/O scheduler & dpkg nodoc..."
if [[ -f /etc/default/grub ]] && ! grep -q "mitigations=off" /etc/default/grub; then
  sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\([^"]*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 mitigations=off"/' /etc/default/grub
  update-grub 2>/dev/null || true
fi

if ! grep -q "noatime" /etc/fstab; then
  sed -i 's/\(defaults\)/\1,noatime,nodiratime/' /etc/fstab
  mount -o remount / 2>/dev/null || true
fi

echo 'ACTION=="add|change", KERNEL=="sd[a-z]|vd[a-z]|nvme[0-9]*", ATTR{queue/scheduler}="none"' > /etc/udev/rules.d/60-io-scheduler.rules
udevadm control --reload-rules && udevadm trigger

cat << 'EOF' > /etc/dpkg/dpkg.cfg.d/01_nodoc
path-exclude=/usr/share/doc/*
path-exclude=/usr/share/man/*
path-exclude=/usr/share/info/*
EOF

echo "[8/8] Setting DMZ accept-all firewall policy..."
if command -v iptables >/dev/null 2>&1; then
  iptables -F && iptables -X
  iptables -t nat -F 2>/dev/null || true
  iptables -t mangle -F 2>/dev/null || true
  iptables -P INPUT ACCEPT
  iptables -P FORWARD ACCEPT
  iptables -P OUTPUT ACCEPT
fi

echo "=============================================================================="
echo "Optimization complete! Rebooting in 5 seconds to apply kernel/GRUB changes..."
echo "=============================================================================="
sleep 5
reboot