# /srv/salt/kvm/verify-host.sls
# Step 8: Validate VM Configuration and Host Readiness
#
# What this does
#  - Verifies CPU virtualization flags, KVM kernel modules, /dev/kvm access
#  - Checks RAM and disk-space thresholds
#  - Confirms libvirt/qemu services are running
#  - Verifies OVMF (UEFI) firmware presence
#  - Verifies swtpm availability and TPM socket dir
#  - Confirms required libvirt networks and VM wiring
#  - Prints a clear PASS/FAIL summary and returns non-zero on failure
#
# How to run (local mode):
#   salt-call --local state.apply kvm.verify-host
#
# Optional pillar knobs (with defaults):
#   kvm:
#     vm_name: win11-base
#     min_ram_mb: 4096          # Minimum host RAM (MB)
#     min_cpu_cores: 2          # Minimum CPU cores
#     min_disk_gb: 10           # Minimum free space on images dir
#     images_dir: /var/lib/libvirt/images
#     bridge_network: edge-bridge
#     require_tpm: true         # Enforce TPM presence in VM XML
#     require_uefi: true        # Enforce OVMF loader presence in VM XML

{% set VM_NAME        = salt['pillar.get']('kvm:vm_name', 'win11-base') %}
{% set MIN_RAM_MB     = salt['pillar.get']('kvm:min_ram_mb', 4096) %}
{% set MIN_CPU_CORES  = salt['pillar.get']('kvm:min_cpu_cores', 2) %}
{% set MIN_DISK_GB    = salt['pillar.get']('kvm:min_disk_gb', 10) %}
{% set IMAGES_DIR     = salt['pillar.get']('kvm:images_dir', '/var/lib/libvirt/images') %}
{% set BR_NET         = salt['pillar.get']('kvm:bridge_network', 'edge-bridge') %}
{% set REQUIRE_TPM    = salt['pillar.get']('kvm:require_tpm', True) %}
{% set REQUIRE_UEFI   = salt['pillar.get']('kvm:require_uefi', True) %}

# Ensure core libvirt daemons are up (idempotent)
verify-host-services:
  service.running:
    - names:
      - virtnetworkd
      - virtqemud
    - enable: True

# Single, readable PASS/FAIL summary with non-zero exit on any failure
verify-host-summary:
  cmd.run:
    - name: |
        set -euo pipefail

        FAIL=0
        warn() { printf "WARN: %s\n" "$*"; }
        pass() { printf "PASS: %s\n" "$*"; }
        fail() { printf "FAIL: %s\n" "$*"; FAIL=$((FAIL+1)); }

        echo "=== Host & VM Readiness Validation ==="
        echo "VM: {{ VM_NAME }}"
        echo

        # ---------- CPU virtualization flags ----------
        if egrep -q '(vmx|svm)' /proc/cpuinfo; then
          pass "CPU virtualization flag present (vmx/svm)"
        else
          fail "CPU virtualization flag NOT present (vmx/svm missing)"
        fi

        # ---------- CPU cores threshold ----------
        CORES="$(nproc || echo 0)"
        if [ "${CORES:-0}" -ge {{ MIN_CPU_CORES }} ]; then
          pass "CPU cores >= {{ MIN_CPU_CORES }} (detected: ${CORES})"
        else
          fail "CPU cores insufficient: need >= {{ MIN_CPU_CORES }}, found ${CORES}"
        fi

        # ---------- KVM modules & /dev/kvm ----------
        if lsmod | grep -qE 'kvm_(intel|amd)'; then
          pass "KVM vendor module loaded"
        else
          # Check generic kvm presence to produce better hint
          if lsmod | grep -q '^kvm\s'; then
            fail "Vendor KVM module (kvm_intel or kvm_amd) not loaded"
          else
            fail "KVM modules not loaded"
          fi
        fi

        if [ -e /dev/kvm ]; then
          if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
            pass "/dev/kvm accessible (rw)"
          else
            fail "/dev/kvm exists but access denied (check group membership, e.g. kvm/libvirt)"
          fi
        else
          fail "/dev/kvm not present"
        fi

        # ---------- RAM threshold ----------
        TOTAL_MB="$(free -m | awk '/^Mem:/{print $2}')"
        if [ -n "${TOTAL_MB}" ] && [ "${TOTAL_MB}" -ge {{ MIN_RAM_MB }} ]; then
          pass "Host RAM >= {{ MIN_RAM_MB }} MB (detected: ${TOTAL_MB} MB)"
        else
          fail "Insufficient host RAM: need >= {{ MIN_RAM_MB }} MB, found ${TOTAL_MB:-unknown}"
        fi

        # ---------- Disk free on images dir ----------
        if [ -d "{{ IMAGES_DIR }}" ]; then
          FREE_GB="$(df -BG "{{ IMAGES_DIR }}" | awk 'NR==2{gsub(/G/,"",$4); print $4}')"
          if [ -n "${FREE_GB}" ] && [ "${FREE_GB}" -ge {{ MIN_DISK_GB }} ]; then
            pass "Free space on {{ IMAGES_DIR }} >= {{ MIN_DISK_GB }} GB (detected: ${FREE_GB} GB)"
          else
            fail "Low free space on {{ IMAGES_DIR }}: need >= {{ MIN_DISK_GB }} GB, found ${FREE_GB:-unknown} GB"
          fi
        else
          fail "Images dir {{ IMAGES_DIR }} not found"
        fi

        # ---------- OVMF (UEFI) presence ----------
        OVMF_FOUND="no"
        for CAND in \
          /usr/share/OVMF/OVMF_CODE.secboot.fd \
          /usr/share/edk2/ovmf/OVMF_CODE.secboot.fd \
          /usr/share/OVMF/OVMF_CODE.fd \
          /usr/share/edk2/x64/OVMF_CODE.fd \
          /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
          /usr/share/edk2/ovmf/OVMF_CODE_x64.fd \
          /usr/share/edk2/ovmf/OVMF_CODE.ms.fd \
          ; do
          if [ -f "$CAND" ]; then
            OVMF_FOUND="yes"
            OVMF_PATH="$CAND"
            break
          fi
        done

        if [ "${OVMF_FOUND}" = "yes" ]; then
          pass "OVMF present (${OVMF_PATH})"
        else
          if {{ "true" if REQUIRE_UEFI else "false" }}; then
            fail "OVMF not found (required)"
          else
            warn "OVMF not found (not strictly required by pillar)"
          fi
        fi

        # ---------- swtpm presence & libvirt tpm dir ----------
        if command -v swtpm >/dev/null 2>&1; then
          pass "swtpm available"
        else
          if {{ "true" if REQUIRE_TPM else "false" }}; then
            fail "swtpm not installed (required)"
          else
            warn "swtpm not installed (not strictly required by pillar)"
          fi
        fi

        # Recent distros use /var/lib/libvirt/swtpm; older ones /var/lib/libvirt/qemu/swtpm
        TPM_DIR=""
        for D in /var/lib/libvirt/swtpm /var/lib/libvirt/qemu/swtpm; do
          if [ -d "$D" ]; then TPM_DIR="$D"; break; fi
        done
        if [ -n "${TPM_DIR}" ]; then
          pass "TPM socket dir present (${TPM_DIR})"
        else
          if {{ "true" if REQUIRE_TPM else "false" }}; then
            fail "TPM socket dir not found (/var/lib/libvirt/swtpm or /var/lib/libvirt/qemu/swtpm)"
          else
            warn "TPM socket dir not found"
          fi
        fi

        # ---------- libvirt network(s) ----------
        BR_OK="no"
        if virsh net-info "{{ BR_NET }}" >/dev/null 2>&1; then
          if virsh net-info "{{ BR_NET }}" 2>/dev/null | awk -F': *' '/Active/{print tolower($2)}' | grep -q yes; then
            BR_OK="yes"
          fi
        fi
        if [ "${BR_OK}" = "yes" ]; then
          pass "Libvirt bridge '{{ BR_NET }}' is defined and active"
        else
          fail "Libvirt bridge '{{ BR_NET }}' missing or inactive"
        fi

        # ---------- VM checks ----------
        if virsh dominfo "{{ VM_NAME }}" >/dev/null 2>&1; then
          pass "VM '{{ VM_NAME }}' is defined"
          echo
          echo "--- virsh dominfo {{ VM_NAME }} ---"
          virsh dominfo "{{ VM_NAME }}" || true
          echo "-----------------------------------"
          echo

          XML="$(virsh dumpxml "{{ VM_NAME }}" 2>/dev/null || true)"

          if {{ "true" if REQUIRE_UEFI else "false" }}; then
            if echo "${XML}" | grep -q "<loader "; then
              pass "VM XML contains UEFI <loader> element"
            else
              fail "VM XML missing UEFI <loader> element"
            fi
          else
            if echo "${XML}" | grep -q "<loader "; then
              pass "VM XML has UEFI <loader> (present but not strictly required)"
            else
              warn "VM XML has no UEFI <loader> (not strictly required by pillar)"
            fi
          fi

          if {{ "true" if REQUIRE_TPM else "false" }}; then
            if echo "${XML}" | grep -q "<tpm[ >]; then
              pass "VM XML contains TPM device"
            else
              fail "VM XML missing TPM device"
            fi
          else
            if echo "${XML}" | grep -q "<tpm[ >]; then
              pass "VM XML has TPM (present but not strictly required)"
            else
              warn "VM XML has no TPM (not strictly required by pillar)"
            fi
          fi

          # NIC attached to target libvirt network?
          if virsh domiflist "{{ VM_NAME }}" | awk 'NR>2 && $0!~/^[- ]*$/ {print $2,$3}' | grep -q "bridge {{ BR_NET }}"; then
            pass "VM NIC attached to '{{ BR_NET }}'"
          else
            fail "VM NIC not attached to '{{ BR_NET }}'"
          fi

        else
          fail "VM '{{ VM_NAME }}' is NOT defined in libvirt"
        fi

        echo
        echo "=== Summary: $( [ $FAIL -eq 0 ] && echo 'ALL CHECKS PASSED' || echo "$FAIL FAILURE(S)" ) ==="
        exit $FAIL
    - require:
      - service: verify-host-services
    - env:
      - LC_ALL: C

