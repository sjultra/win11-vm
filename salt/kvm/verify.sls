{# CPU virtualization flags present? #}
virt-cpu-flags:
  cmd.run:
    - name: "egrep -c '(vmx|svm)' /proc/cpuinfo"
    - success_retcodes:
      - 0
      - 1   # still returns 0/1; we just want output
    - require:
      - service: libvirtd-service

{# /dev/kvm present for acceleration #}
dev-kvm-present:
  cmd.run:
    - name: "test -c /dev/kvm && echo PASS || (echo 'FAIL: /dev/kvm missing' && false)"

{# libvirt responds #}
libvirt-connect:
  cmd.run:
    - name: "virsh -c qemu:///system list --all >/dev/null && echo PASS || (echo 'FAIL: cannot connect to libvirt' && false)"

{# Show versions for sanity #}
versions-dump:
  cmd.run:
    - name: |
        echo '--- Versions ---'
        libvirtd --version || true
        qemu-system-x86_64 --version || true
        swtpm --version || true
        rpm -q edk2-ovmf 2>/dev/null || dpkg -l | grep -E 'ovmf|edk2' || true
