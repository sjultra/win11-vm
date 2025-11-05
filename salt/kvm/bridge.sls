# /srv/salt/kvm/bridge.sls
#
# Purpose:
#   Define and ensure a persistent NetworkManager bridge (br0)
#   that uses enp1s0f0 as its slave. This bridge replaces
#   standalone Wired connection profiles and allows VMs to use
#   bridged networking (no NAT, no dnsmasq conflicts).

networkmanager-bridge-package:
  pkg.installed:
    - name: NetworkManager

# Ensure NetworkManager service is running
networkmanager-service:
  service.running:
    - name: NetworkManager
    - enable: True

# Create bridge connection br0 if not exists
nmcli-create-bridge:
  cmd.run:
    - name: |
        if ! nmcli connection show br0 >/dev/null 2>&1; then
          nmcli connection add type bridge ifname br0 con-name br0 ipv4.method auto ipv6.method auto
        fi
    - unless: nmcli connection show br0 >/dev/null 2>&1
    - require:
      - pkg: networkmanager-bridge-package

# Create bridge-slave for enp1s0f0 if not exists
nmcli-add-slave:
  cmd.run:
    - name: |
        if ! nmcli connection show br0-slave-enp1s0f0 >/dev/null 2>&1; then
          nmcli connection add type bridge-slave ifname enp1s0f0 con-name br0-slave-enp1s0f0 master br0
        fi
    - unless: nmcli connection show br0-slave-enp1s0f0 >/dev/null 2>&1
    - require:
      - cmd: nmcli-create-bridge

# Bring bridge and slave up
nmcli-up-bridge:
  cmd.run:
    - name: |
        nmcli connection up br0-slave-enp1s0f0 || true
        nmcli connection up br0 || true
    - require:
      - cmd: nmcli-add-slave

# Disable old standalone NIC config if still present
nmcli-disable-old-wired:
  cmd.run:
    - name: |
        if nmcli connection show "Wired connection 1" >/dev/null 2>&1; then
          nmcli connection down "Wired connection 1" || true
        fi
    - onlyif: nmcli connection show "Wired connection 1" >/dev/null 2>&1

# Optionally delete it once validated (commented out for safety)
# nmcli-delete-old-wired:
#   cmd.run:
#     - name: nmcli connection delete "Wired connection 1"
#     - onlyif: nmcli connection show "Wired connection 1" >/dev/null 2>&1
#     - require:
#       - cmd: nmcli-disable-old-wired

# Final verification for logging
bridge-verify:
  cmd.run:
    - name: |
        echo "--- Bridge Summary ---"
        nmcli device status
        ip -4 addr show br0
        echo "--- End Summary ---"

