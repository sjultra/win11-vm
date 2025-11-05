# /srv/salt/kvm/network.sls
# Idempotent libvirt bridge network + VM NIC attach
# Uses br0 created by kvm.bridge state (NetworkManager).
# Pillars (with sensible defaults):
#   kvm:vms:win11-base:mac -> fixed MAC (default: 52:54:00:11:22:33)
#   kvm:vms:win11-base:name -> VM name (default: win11-base)

{% set BRIDGE_XML = '/etc/libvirt/qemu/networks/edge-bridge.xml' %}
{% set VM_NAME   = salt['pillar.get']('kvm:vms:win11-base:name', 'win11-base') %}
{% set WIN11_MAC = salt['pillar.get']('kvm:vms:win11-base:mac',  '52:54:00:11:22:33') %}

virtnetworkd-service:
  service.running:
    - name: virtnetworkd
    - enable: True

virtqemud-service:
  service.running:
    - name: virtqemud
    - enable: True

edge-bridge-xml:
  file.managed:
    - name: {{ BRIDGE_XML }}
    - mode: "0644"
    - makedirs: True
    - contents: |
        <network>
          <name>edge-bridge</name>
          <forward mode='bridge'/>
          <bridge name='br0'/>
        </network>
    - require:
      - service: virtnetworkd-service
      - service: virtqemud-service

# If an edge-bridge exists but is transient (Persistent: no), destroy it so we can define persistently
edge-bridge-destroy-transient:
  cmd.run:
    - name: virsh net-destroy edge-bridge
    - onlyif: "virsh net-info edge-bridge 2>/dev/null | grep -q 'Persistent: *no'"
    - require:
      - file: edge-bridge-xml
    - onchanges_in:
      - cmd: edge-bridge-define

# Define persistently if not already
edge-bridge-define:
  cmd.run:
    - name: virsh net-define {{ BRIDGE_XML }}
    - unless: "virsh net-info edge-bridge 2>/dev/null | grep -q 'Persistent: *yes'"
    - require:
      - file: edge-bridge-xml

# Clean up a stale/broken autostart link before setting autostart
edge-bridge-autostart-clean:
  cmd.run:
    - name: |
        set -e
        LINK="/etc/libvirt/qemu/networks/autostart/edge-bridge.xml"
        # If network is persistent but autostart isn't reported as yes and a link exists, remove it
        if virsh net-info edge-bridge 2>/dev/null | grep -q 'Persistent: *yes'; then
          if [ -L "$LINK" ] && ! virsh net-info edge-bridge 2>/dev/null | grep -q 'Autostart: *yes'; then
            rm -f "$LINK"
          fi
        fi
    - require:
      - cmd: edge-bridge-define

# Set autostart if not already
edge-bridge-autostart:
  cmd.run:
    - name: virsh net-autostart edge-bridge
    - unless: "virsh net-info edge-bridge 2>/dev/null | grep -q 'Autostart: *yes'"
    - require:
      - cmd: edge-bridge-autostart-clean

# Start the network (do NOT strictly depend on autostart to avoid blocking bring-up)
edge-bridge-start:
  cmd.run:
    - name: virsh net-start edge-bridge
    - unless: "virsh net-info edge-bridge 2>/dev/null | grep -q 'Active: *yes'"
    - require:
      - cmd: edge-bridge-define

# Detach default network if still present (persistently)
{{ VM_NAME }}-detach-default-net:
  cmd.run:
    - name: |
        set -e
        if virsh dumpxml {{ VM_NAME }} | grep -q "<source network='default'"; then
          DEF_MAC="$(virsh domiflist {{ VM_NAME }} | awk '/ default /{print $5; exit}')"
          if [ -n "$DEF_MAC" ]; then
            virsh detach-interface {{ VM_NAME }} --type network --mac "$DEF_MAC" --config || true
          fi
        fi
    - require:
      - cmd: edge-bridge-start

# Attach the VM NIC to edge-bridge with a fixed MAC (persistently)
{{ VM_NAME }}-attach-bridge:
  cmd.run:
    - name: |
        set -e
        if ! virsh dumpxml {{ VM_NAME }} | grep -q "<source network='edge-bridge'"; then
          virsh attach-interface {{ VM_NAME }} --type network --source edge-bridge \
            --model virtio --mac {{ WIN11_MAC }} --config
        fi
    - require:
      - cmd: {{ VM_NAME }}-detach-default-net

edge-bridge-summary:
  cmd.run:
    - name: |
        echo "--- Bridge Network Summary ---"
        virsh net-info edge-bridge || echo "edge-bridge not defined"
        echo
        echo "VM NICs for {{ VM_NAME }}:"
        virsh domiflist {{ VM_NAME }} || echo "{{ VM_NAME }} not defined"
        echo "--- End Summary ---"
    - require:
      - cmd: {{ VM_NAME }}-attach-bridge

