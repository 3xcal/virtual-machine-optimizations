# Virtual Machine Optimizations

Bare-metal performance tuning and debloat automation scripts for resource-constrained Ubuntu cloud virtual machines (1 GB RAM shapes, VPN/proxy nodes, and lightweight containers).

Strips idle Ubuntu cloud images down to **~70–80 MB headless idle RAM**, eliminates background CPU/I/O spikes, disables swap overhead, enables TCP BBR, and unlocks raw syscall throughput while preserving critical boot dependencies.

---

## Available Scripts

| Script | Target Environment | Key Behavior |
| :--- | :--- | :--- |
| **`VM.Standard.E2.1.Micro.sh`** | Oracle Cloud Infrastructure (OCI) `VM.Standard.E2.1.Micro` (AMD) & `A1.Flex` (ARM) | Removes `snapd` and `oracle-cloud-agent`, preserves `iscsid` (required for OCI iSCSI root boot volume), and sets an `ACCEPT`-all DMZ firewall policy (relying on OCI Security Lists/NSGs). |
| **`ubuntu-cloud-optimize.sh`** *(Optional)* | Generic Ubuntu 20.04 / 22.04 / 24.04 Cloud VMs (AWS EC2, GCP, DigitalOcean, Hetzner, Vultr, Linode, KVM) | Provider-agnostic debloat and kernel/I/O tuning without Oracle-specific removals or firewall flushes. |

---

## What Gets Optimized

* **Snapd & Cloud Telemetry Removal:** Purges `snapd`, `squashfs-tools`, and `oracle-cloud-agent` (on OCI), unmounting `/snap` loop devices and reclaiming ~100–250 MB of resident RAM.
* **Background Daemon Pruning:** Removes idle Python watchers and hardware managers (`unattended-upgrades`, `networkd-dispatcher`, `multipath-tools`, `rpcbind`, `atd`, `apport`, `whoopsie`, `avahi-daemon`, `fwupd`, `udisks2`, `bolt`, `pollinate`, `systemd-oomd`).
* **Timers, TTYs & Boot Speed:** Disables periodic `apt-daily` and `motd` timers, masks unused serial/local TTY consoles (`ttyS0`, `tty1`), disables `systemd-timesyncd`, and writes `/etc/cloud/cloud-init.disabled` for fast ~15–25s reboots.
* **Static Upstream DNS:** Replaces `systemd-resolved` (~13 MB RAM) with direct static resolution (`1.1.1.1` and `8.8.8.8`).
* **Zero-RAM / Zero-Disk Logging:** Configures `systemd-journald` with `Storage=none` (0 MB log buffer in RAM and disk) while keeping `/dev/log` open so services never hang.
* **Zero Swap & TCP BBR Networking:** Disables swap (`vm.swappiness=0`), enables Google TCP BBR congestion control with Fair Queueing (`fq`), expands TCP socket buffers to 16 MB, enables IPv4 forwarding, and disables IPv6 stack overhead.
* **Raw CPU & Disk I/O:** Disables Spectre/Meltdown kernel mitigations (`mitigations=off`) via `/etc/default/grub.d/99-mitigations-off.cfg` for a 10–25% syscall boost on older EPYC CPUs, mounts `/` with `noatime,nodiratime`, sets the block I/O scheduler to `none`, and blocks future `apt` installs from writing docs/manpages.

---

## Quick Start

> **Important:** Run over an **SSH session** after initial VM provisioning completes. Do **not** run the OCI script via Oracle's Web Console "Run Command" plugin, as removing `oracle-cloud-agent` mid-run will sever the console agent before completion.

### Using `wget` (Pre-installed on Ubuntu)
```bash
wget -qO- [https://raw.githubusercontent.com/3xcal/virtual-machine-optimizations/main/VM.Standard.E2.1.Micro.sh](https://raw.githubusercontent.com/3xcal/virtual-machine-optimizations/main/VM.Standard.E2.1.Micro.sh) | sudo bash
