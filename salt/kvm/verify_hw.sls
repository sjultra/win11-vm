{# ---- Resolve OVMF paths from pillar with sensible defaults ---- #}
{% set uefi_code = salt['pillar.get']('windows_vms:uefi_code', '/usr/share/OVMF/OVMF_CODE.secboot.fd') %}
{% set uefi_vars = salt['pillar.get']('windows_vms:uefi_vars_template', '/usr/share/OVMF/OVMF_VARS.secboot.fd') %}

{# ---- Helper commands (don’t fail run; we handle PASS/FAIL ourselves) ---- #}
virt-flags-check:
  cmd.run:
    - name: |
        CNT=$(egrep -c '(vmx|svm)' /proc/cpuinfo || echo 0)
        if [ "$CNT" -ge 1 ]; then
          echo "PASS: CPU virtualization flags present (count=$CNT)"
          exit 0
        else
          echo "FAIL: No VT-x/AMD-V flags detected"
          exit 1
        fi

kvm-device-check:
  cmd.run:
    - name: |
        if [ -c /dev/kvm ]; then
          echo "PASS: /dev/kvm present"
          exit 0
        else
          echo "FAIL: /dev/kvm missing"
          exit 1
        fi

swtpm-availability:
  cmd.run:
    - name: |
        if command -v swtpm >/dev/null 2>&1; then
          echo "PASS: swtpm available ($(
            swtpm --version 2>/dev/null | head -n1
          ))"
          exit 0
        else
          echo "FAIL: swtpm not installed (required for TPM emulation)"
          exit 1
        fi

tpm-device-check:
  cmd.run:
    - name: |
        if [ -e /dev/tpmrm0 ] || [ -e /dev/tpm0 ]; then
          DEV=$([ -e /dev/tpmrm0 ] && echo /dev/tpmrm0 || echo /dev/tpm0)
          echo "INFO: Hardware TPM detected at ${DEV}"
          exit 0
        else
          echo "INFO: No hardware TPM node found; emulation via swtpm will be required"
          exit 0
        fi

ovmf-secboot-code-check:
  cmd.run:
    - name: |
        if [ -f "{{ uefi_code }}" ]; then
          echo "PASS: OVMF secure-boot code present: {{ uefi_code }}"
          exit 0
        else
          echo "FAIL: OVMF secure-boot code not found at {{ uefi_code }}"
          exit 1
        fi

ovmf-secboot-vars-check:
  cmd.run:
    - name: |
        if [ -f "{{ uefi_vars }}" ]; then
          echo "PASS: OVMF secure-boot VARS template present: {{ uefi_vars }}"
          exit 0
        else
          echo "FAIL: OVMF secure-boot VARS template not found at {{ uefi_vars }}"
          exit 1
        fi

host-secureboot-state:
  cmd.run:
    - name: |
        if command -v mokutil >/dev/null 2>&1; then
          STATE=$(mokutil --sb-state 2>/dev/null || true)
          echo "INFO: Host UEFI Secure Boot state: ${STATE:-unknown}"
          exit 0
        else
          echo "INFO: mokutil not installed; skipping host SB check"
          exit 0
        fi

cpu-summary:
  cmd.run:
    - name: |
        MODEL=$(awk -F': *' '/model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null)
        VENDOR=$(awk -F': *' '/vendor_id/{print $2; exit}' /proc/cpuinfo 2>/dev/null)
        echo "INFO: CPU vendor=${VENDOR:-unknown}, model=${MODEL:-unknown}"
        exit 0

versions-summary:
  cmd.run:
    - name: |
        echo "--- Versions ---"
        libvirtd --version 2>/dev/null || echo "libvirtd: n/a"
        qemu-system-x86_64 --version 2>/dev/null || echo "qemu-system-x86_64: n/a"
        swtpm --version 2>/dev/null || echo "swtpm: n/a"
        rpm -q edk2-ovmf 2>/dev/null || dpkg -l | grep -E 'ovmf|edk2' || echo "ovmf/edk2: n/a"
        exit 0

{# ---- Aggregate a simple text report to /var/log/virt_support_report.txt ---- #}
virt-support-report:
  cmd.run:
    - name: |
        {
          date
          echo "== Virtualization & Firmware Support Report =="
          egrep -c '(vmx|svm)' /proc/cpuinfo 2>/dev/null | awk '{print ($1>0)?"PASS: CPU flags present (count="$1")":"FAIL: No VT-x/AMD-V flags"}'
          [ -c /dev/kvm ] && echo "PASS: /dev/kvm present" || echo "FAIL: /dev/kvm missing"
          if command -v swtpm >/dev/null 2>&1; then
            echo "PASS: swtpm available ($(
              swtpm --version 2>/dev/null | head -n1
            ))"
          else
            echo "FAIL: swtpm not installed"
          fi
          [ -e /dev/tpmrm0 ] && echo "INFO: Hardware TPM at /dev/tpmrm0" || true
          [ -e /dev/tpm0 ] && echo "INFO: Hardware TPM at /dev/tpm0" || true
          [ -f "{{ uefi_code }}" ] && echo "PASS: OVMF code: {{ uefi_code }}" || echo "FAIL: Missing OVMF code: {{ uefi_code }}"
          [ -f "{{ uefi_vars }}" ] && echo "PASS: OVMF VARS: {{ uefi_vars }}" || echo "FAIL: Missing OVMF VARS: {{ uefi_vars }}"
          if command -v mokutil >/dev/null 2>&1; then
            mokutil --sb-state 2>/dev/null || true
          else
            echo "INFO: mokutil not installed; host SB state skipped"
          fi
          echo "--- Versions ---"
          libvirtd --version 2>/dev/null || echo "libvirtd: n/a"
          qemu-system-x86_64 --version 2>/dev/null || echo "qemu-system-x86_64: n/a"
          swtpm --version 2>/dev/null || echo "swtpm: n/a"
          rpm -q edk2-ovmf 2>/dev/null || dpkg -l | grep -E 'ovmf|edk2' || echo "ovmf/edk2: n/a"
          echo
        } | tee /var/log/virt_support_report.txt
    - require:
      - cmd: virt-flags-check
      - cmd: kvm-device-check
      - cmd: swtpm-availability
      - cmd: tpm-device-check
      - cmd: ovmf-secboot-code-check
      - cmd: ovmf-secboot-vars-check
      - cmd: host-secureboot-state
      - cmd: cpu-summary
      - cmd: versions-summary

