# /srv/pillar/kvm.sls
kvm:
  # Host bridge device that already exists and has LAN connectivity
  bridge_name: br0

  # Libvirt "network" wrapper name that forwards to the host bridge
  bridge_net_name: edge-bridge

  # Fixed MAC(s) for VMs (reserve these in upstream DHCP server)
  vms:
    win11-base:
      mac: '52:54:00:11:22:33'

  vm_name: win11-base

  require_tpm: true          # keep this true to enforce the check

  tpm_model: tpm-tis         # good default; use 'tpm-crb' for q35 machine types
