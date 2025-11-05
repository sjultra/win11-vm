{# Pillar with safe defaults #}
{% set VM_NAME   = salt['pillar.get']('kvm:vm_name', 'win11-base') %}
{% set TPM_MODEL = salt['pillar.get']('kvm:tpm_model', 'tpm-tis') %}

# 1) Ensure swtpm tool is available
kvm-tpm-pkg:
  pkg.installed:
    - name: swtpm

# 2) Ensure typical TPM socket dirs exist (varies by distro)
kvm-tpm-sockdir:
  file.directory:
    - names:
      - /var/lib/libvirt/swtpm
      - /var/lib/libvirt/qemu/swtpm
    - makedirs: True
    - require:
      - pkg: kvm-tpm-pkg

# 3) Gracefully shut down the VM if it's running (required to redefine)
kvm-tpm-stop-domain-if-running:
  cmd.run:
    - name: |
        set -e
        if virsh dominfo "{{ VM_NAME }}" >/dev/null 2>&1; then
          STATE="$(virsh domstate "{{ VM_NAME }}" 2>/dev/null | tr '[:upper:]' '[:lower:]')"
          if [ "$STATE" = "running" ] || [ "$STATE" = "paused" ]; then
            virsh shutdown "{{ VM_NAME }}" || true
            # Wait up to ~120s for shutoff
            for i in $(seq 1 24); do
              STATE="$(virsh domstate "{{ VM_NAME }}" 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"
              [ "$STATE" = "shut off" ] && break
              sleep 5
            done
          fi
        fi
    - require:
      - file: kvm-tpm-sockdir

# 4) Dump inactive domain XML and persist to a working path
kvm-tpm-dump-xml:
  cmd.run:
    - name: |
        set -e
        virsh dumpxml --inactive "{{ VM_NAME }}" > /etc/libvirt/qemu/{{ VM_NAME }}.xml
    - require:
      - cmd: kvm-tpm-stop-domain-if-running

# 5) Patch XML to add TPM if missing, then redefine the domain
kvm-tpm-redefine:
  cmd.run:
    - name: |
        set -e
        SRC="/etc/libvirt/qemu/{{ VM_NAME }}.xml"
        DST="/etc/libvirt/qemu/{{ VM_NAME }}-with-tpm.xml"

        # If TPM already present, just copy through
        if grep -q '<tpm' "$SRC"; then
          cp -f "$SRC" "$DST"
        else
          awk '
            BEGIN { added=0 }
            /<\/devices>/ && added==0 {
              print "    <tpm model='\''{{ TPM_MODEL }}'\''>"
              print "      <backend type='\''emulator'\'' version='\''2.0'\''/>"
              print "    </tpm>"
              added=1
            }
            { print }
          ' "$SRC" > "$DST"
        fi

        # Ensure well-formed XML by letting libvirt validate on define
        virsh define "$DST"
    - require:
      - cmd: kvm-tpm-dump-xml

# 6) (Optional) Start the VM again if it was shut off
kvm-tpm-start-domain:
  cmd.run:
    - name: |
        STATE="$(virsh domstate "{{ VM_NAME }}" 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"
        if [ "$STATE" = "shut off" ]; then
          virsh start "{{ VM_NAME }}"
        fi
    - require:
      - cmd: kvm-tpm-redefine

