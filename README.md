# Windows 11 Virtualization (SaltStack + QEMU/KVM)
## Temporary Orchestration Setup (VSP-129)

This repository provides a **temporary standalone SaltStack environment** for provisioning and managing a pre-built Windows 11 VM using **QEMU / KVM / Libvirt** on both **RHEL** and **Debian-based** systems. It is designed as a transitional structure before merging into the main `/data/salt` architecture.

NOTE: The .qcow2 image referenced at `/var/lib/libvirt/images/Windows11.qcow2` in this setup is **NOT configured**, and will not provide an operating version of windows. In production it will be replaced with the fully configured windows 11 pro .qcow2 image located at `/data/repo/software/linux/win11-pro.qcow2` on stl-prod-ops-adm-01.sjultra.com.
If you are attempting to use this repository to launch a working version of windows 11 make sure to take the win11-pro.qcow2 on stl-prod-ops and copy / rename it to `/var/lib/libvirt/images/Windows11.qcow2`

The Salt states automate installation, validation, image registration, and network configuration—but every automated step can also be executed **manually** (documented below) for direct troubleshooting or replication.

---

## Table of Contents
1. [Repository Layout](#repository-layout)
2. [Environment Overview](#environment-overview)
3. [Salt Usage](#salt-usage)
4. [Manual Procedures](#manual-procedures)
   - [1. Install KVM / QEMU / Libvirt](#1-install-kvm-qemu-libvirt)
   - [2. Verify Virtualization Support](#2-verify-virtualization-support)
   - [3. Configure TPM and UEFI Firmware](#3-configure-tpm-and-uefi-firmware)
   - [4. Validate and Prepare Windows Images](#4-validate-and-prepare-windows-images)
   - [5. Define and Register VMs](#5-define-and-register-vms)
   - [6. Configure Networking (Bridge Mode)](#6-configure-networking-bridge-mode)
   - [7. Manage VM Lifecycle](#7-manage-vm-lifecycle)
5. [RDP Access and VirtIO Drivers](#rdp-access-and-virtio-drivers)
6. [Troubleshooting and Validation](#troubleshooting-and-validation)

---

## Repository Layout

```
/srv/
├── salt/
│   ├── kvm/
│   │   ├── init.sls          # Install and enable virtualization stack
│   │   ├── verify_hw.sls     # Hardware & firmware validation
│   │   ├── tpm_uefi.sls      # Configure swtpm + OVMF
│   │   ├── images.sls        # Validate qcow2 images exists
│   │   ├── define.sls        # Define VM via XML
│   │   ├── network.sls       # Define persistent libvirt bridge
│   │   ├── manage.sls        # Start/stop/status orchestration
│   │   └── templates/
│   │       ├── win11-base.xml
│   │       └── qemu.conf.j2
│   └── top.sls
└── pillar/
    ├── virt_common.sls
    ├── windows_vms.sls
    └── top.sls
```

---

## Environment Overview
- **Target Hosts:** RHEL 9 / Rocky 9 / Debian 12  
- **Guest OS:** Windows 11 (pre-built `.qcow2`)  
- **Network Mode:** Bridged (`br0` → `edge-bridge`)  
- **Access Method:** RDP (via DHCP-assigned IP)  
- **Firmware & TPM:** OVMF Secure Boot + swtpm 2.0  

This setup intentionally lives under `/srv/` to isolate it from production Salt trees (`/data/salt/`).

---

## Salt Usage

**Dry-Run**
```bash
sudo salt-call --local state.apply test=True
```

**Apply Full Stack**
```bash
sudo salt-call --local state.apply
```

**Target Specific Steps**
```bash
sudo salt-call --local state.apply kvm.init
sudo salt-call --local state.apply kvm.verify_hw
sudo salt-call --local state.apply kvm.tpm_uefi
sudo salt-call --local state.apply kvm.images
sudo salt-call --local state.apply kvm.define
sudo salt-call --local state.apply kvm.network
```

**Manage VMs**
```bash
salt-call --local state.apply kvm.manage pillar='{"action": "start"}'
salt-call --local state.apply kvm.manage pillar='{"action": "stop"}'
salt-call --local state.apply kvm.manage pillar='{"action": "restart"}'
salt-call --local state.apply kvm.manage pillar='{"action": "status"}'
```

---

## Manual Procedures

---

### 1. Install KVM / QEMU / Libvirt
**RHEL / Rocky:**
```bash
sudo dnf install -y qemu-kvm libvirt virt-install swtpm edk2-ovmf
sudo systemctl enable --now libvirtd virtqemud virtlogd virtlockd
```

**Debian / Ubuntu:**
```bash
sudo apt install -y qemu-kvm libvirt-daemon-system virtinst swtpm ovmf
sudo systemctl enable --now libvirtd virtqemud virtlogd virtlockd
```

**Verify:**
```bash
egrep -c '(vmx|svm)' /proc/cpuinfo
lsmod | egrep 'kvm(_intel|_amd)?'
systemctl status libvirtd --no-pager
virsh -c qemu:///system list --all
```

---

### 2. Verify Virtualization Support
Confirm the host can run Windows 11:

```bash
egrep -c '(vmx|svm)' /proc/cpuinfo
ls -l /dev/kvm
mokutil --sb-state || true
swtpm socket --version
rpm -q edk2-ovmf || dpkg -l | grep ovmf
```

**Consolidated Report:**
```bash
sudo salt-call --local state.apply kvm.verify_hw
cat /var/log/virt_support_report.txt
```

---

### 3. Configure TPM and UEFI Firmware
```bash
sudo mkdir -p /var/lib/libvirt/swtpm
sudo chown root:root /var/lib/libvirt/swtpm

# Verify TPM emulator
swtpm socket --tpm2 --ctrl type=unixio,path=/tmp/swtpm-test.sock &
ps aux | grep swtpm
kill %1
```

**UEFI Firmware Check**
```bash
ls /usr/share/OVMF/OVMF_CODE.secboot.fd
ls /usr/share/OVMF/OVMF_VARS.secboot.fd
```

---

### 4. Validate and Prepare Image
Ensure qcow2 image exists:
```bash
ls -l /var/lib/libvirt/images/
```

**Permissions**
```bash
sudo chown qemu:qemu /var/lib/libvirt/images/Windows11.qcow2
sudo chmod 660 /var/lib/libvirt/images/Windows11.qcow2
```

**Optional Conversion**
```bash
qemu-img convert -f raw -O qcow2 Win11_25H2.iso /var/lib/libvirt/images/Windows11.qcow2
```

---

### 5. Define and Register VMs
Copy the XML definition and register:

```bash
sudo cp win11-base.xml /etc/libvirt/qemu/
sudo virsh define /etc/libvirt/qemu/win11-base.xml
```

NOTE: win11-base.xml only allocated 4G of RAM to the VM. If you want / need more then change the amount in the XML file before utilizing it. 

```bash
sudo virsh list --all
```

Expected:
```
Id   Name          State
----------------------------
-    win11-base    shut off
```

---

### 6. Configure Networking (Bridge Mode)
**Create Bridge with NetworkManager**
```bash
nmcli connection add type bridge ifname br0 con-name br0 ipv4.method auto
nmcli connection add type bridge-slave ifname enp1s0f0 con-name br0-slave-enp1s0f0 master br0
nmcli connection up br0-slave-enp1s0f0
nmcli connection up br0
```

**Validate**
```bash
brctl show br0
```

**Libvirt Persistent Network**
```bash
virsh net-define /srv/salt/kvm/templates/edge-bridge.xml
virsh net-autostart edge-bridge
virsh net-start edge-bridge
virsh net-info edge-bridge
```

Expected:
```
Name:           edge-bridge
Active:         yes
Persistent:     yes
Autostart:      yes
Bridge:         br0
```

---

### 7. Manage VM Lifecycle
```bash
# Start VM
virsh start win11-base

# Stop VM
virsh shutdown win11-base

# Restart
virsh reboot win11-base

# Delete
virsh undefine win11-base
```

**Service Enablement**
```bash
systemctl enable --now virtqemud.socket virtnetworkd.socket virtstoraged.socket
```

---

## RDP Access and VirtIO Drivers
Once the VM is started:
1. Use `virsh domifaddr win11-base` to find the IP.  
2. Connect via RDP:
   ```
   rdp://<vm_ip>
   ```
3. Default Windows user: **vmuser**  pass: **S-2025** (If using the production image located at `/data/repo/software/linux/win11-pro.qcow2`)
4. If you need to reinstall drivers:
   - Download VirtIO ISO: <https://fedorapeople.org/groups/virt/virtio-win/>
   - Mount with:  
     ```bash
     virsh attach-disk win11-base /usr/share/virtio-win/virtio-win.iso hdc --type cdrom --mode readonly
     ```

---

## Troubleshooting and Validation

| Issue                     | Fix                                                                    |
| ------------------------- | ---------------------------------------------------------------------- |
| `/dev/kvm` missing        | Enable VT-x / AMD-V in BIOS; `modprobe kvm_intel` or `kvm_amd`         |
| User not in libvirt group | `usermod -aG libvirt $USER` then re-login                              |
| OVMF files missing        | `dnf install edk2-ovmf` or `apt install ovmf`                          |
| TPM socket error          | Recreate `/var/lib/libvirt/swtpm`; restart libvirtd                    |
| VM no network             | Verify bridge (`br0`) is up and attached in `virsh domiflist`          |
| Unknown host IP           | Use `arp -n` or check router DHCP leases                               |
| Salt state fails          | Run `state.apply test=True` for syntax then apply modules individually |

---

## References
- `qemu-kvm(1)`, `virsh(1)`, `virt-install(1)`  
- [Libvirt Networking Guide](https://wiki.libvirt.org/page/Networking)  
- [OVMF Secure Boot Firmware](https://github.com/tianocore/edk2)  
- [Fedora VirtIO Drivers for Windows](https://fedorapeople.org/groups/virt/virtio-win/)

---