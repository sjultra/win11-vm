# /srv/salt/kvm/tpm_uefi.sls
# Purpose: ensure TPM emulation and UEFI firmware are ready for Windows 11 guests

tpm-pkg-install:
  pkg.installed:
    - names:
      - swtpm
      - swtpm-tools

tpm-socket-dir:
  file.directory:
    - name: /var/lib/libvirt/swtpm
    - user: root
    - group: root
    - mode: 0755
    - makedirs: True

tpm-test-workdir:
  file.directory:
    - name: /tmp/swtpm-test
    - user: root
    - group: root
    - mode: 0700
    - makedirs: True

tpm-test-instance:
  cmd.run:
    - name: |
        set -euo pipefail
        workdir="/tmp/swtpm-test"
        sock="${workdir}/swtpm.sock"
        pidf="${workdir}/swtpm.pid"
        logf="${workdir}/swtpm.log"

        # ensure clean slate
        rm -f "${sock}" "${pidf}" || true

        # start swtpm in background (daemon) with explicit pid/log files
        swtpm socket \
          --tpmstate dir="${workdir}" \
          --ctrl type=unixio,path="${sock}" \
          --tpm2 \
          --daemon \
          --pid file="${pidf}" \
          --log file="${logf}"

        # wait (up to ~3s) for control socket to appear
        for i in 1 2 3 4 5 6; do
          [ -S "${sock}" ] && break
          sleep 0.5
        done
        if [ ! -S "${sock}" ]; then
          echo "FAIL: swtpm control socket not created at ${sock}"
          echo "--- swtpm log ---"
          cat "${logf}" || true
          exit 1
        fi

        # stop the specific swtpm process we launched
        if [ -s "${pidf}" ]; then
          kill -TERM "$(cat "${pidf}")" 2>/dev/null || true
        else
          echo "WARN: pid file not found; attempting best-effort cleanup"
          pkill -f "swtpm socket" || true
        fi

        echo "PASS: swtpm daemon test executed successfully (socket=${sock})"
    - require:
      - pkg: tpm-pkg-install
      - file: tpm-test-workdir

uefi-firmware-check:
  cmd.run:
    - name: |
        for f in /usr/share/OVMF/OVMF_CODE.secboot.fd /usr/share/OVMF/OVMF_VARS.secboot.fd; do
          if [ -f "$f" ]; then
            echo "PASS: Found $f"
          else
            echo "FAIL: Missing $f"
          fi
        done

uefi-perms:
  file.managed:
    - name: /etc/libvirt/qemu.conf
    - source: salt://kvm/templates/qemu.conf.j2
    - user: root
    - group: root
    - mode: 0644
    - template: jinja
    - require:
      - pkg: tpm-pkg-install

virt-tpm-summary:
  cmd.run:
    - name: |
        echo "--- TPM/UEFI Summary ---"
        command -v swtpm >/dev/null && swtpm --version || echo "swtpm: missing"
        [ -f /usr/share/OVMF/OVMF_CODE.secboot.fd ] && echo "OVMF_CODE.secboot.fd: present" || echo "OVMF_CODE.secboot.fd: missing"
        [ -f /usr/share/OVMF/OVMF_VARS.secboot.fd ] && echo "OVMF_VARS.secboot.fd: present" || echo "OVMF_VARS.secboot.fd: missing"
        echo "TPM socket dir contents:" && ls -ld /var/lib/libvirt/swtpm
        echo "--- End of Summary ---"

