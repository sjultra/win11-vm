# /srv/salt/kvm/verify-network.sls
include:
  - kvm.network

{% set WIN11_MAC = salt['pillar.get']('kvm:vms:win11-base:mac', '52:54:00:11:22:33') %}

win11-base-network-validation:
  cmd.run:
    - name: |
        echo "--- Validating VM Networking ---"
        virsh domiflist win11-base
        virsh net-info edge-bridge
        echo
        echo "Checking ARP table for {{ WIN11_MAC }} ..."
        IP=$(awk '/{{ WIN11_MAC }}/ {print $1}' /proc/net/arp | head -n1)
        if [ -n "$IP" ]; then
          echo "Found IP: $IP"
          ping -c 2 "$IP" || echo "Ping failed (possibly ICMP disabled)"
        else
          echo "MAC {{ WIN11_MAC }} not found in ARP table. Try starting the VM or checking DHCP leases."
        fi
        echo "--- End Validation ---"
    - require:
      - cmd: edge-bridge-summary

