{# -------- Package selection by distro -------- #}
{% set pkgs_override = salt['pillar.get']('virt:pkgs_override', {}) %}
{% set osfam = grains.get('os_family') %}

{% if pkgs_override and pkgs_override.get(osfam) %}
  {% set pkgs = pkgs_override.get(osfam) %}
{% else %}
  {% if osfam == 'RedHat' %}
    {% set pkgs = ['qemu-kvm','libvirt','virt-install','swtpm','edk2-ovmf'] %}
  {% elif osfam == 'Debian' %}
    {% set pkgs = ['qemu-kvm','libvirt-daemon-system','virtinst','swtpm','ovmf'] %}
  {% else %}
    {% set pkgs = ['qemu-kvm','libvirt','virt-install','swtpm','ovmf'] %}
  {% endif %}
{% endif %}

{# -------- Service names (RHEL9 uses libvirtd shim + split daemons) -------- #}
{% if osfam == 'RedHat' %}
  {% set libvirtd_service = 'libvirtd' %}
  {% set extra_services = ['virtqemud','virtlogd','virtlockd'] %}
{% else %}
  {% set libvirtd_service = 'libvirtd' %}
  {% set extra_services = ['virtlogd','virtlockd'] %}
{% endif %}

{# -------- Ensure packages installed -------- #}
kvm-deps:
  pkg.installed:
    - pkgs: {{ pkgs }}

{# -------- Ensure required groups/users for access -------- #}
libvirt-group:
  group.present:
    - name: libvirt

{# Add pillar-specified admin users to libvirt group #}
{% for u in salt['pillar.get']('virt:admin_users', []) %}
libvirt-user-{{ u }}:
  user.present:
    - name: {{ u }}
    - groups:
      - libvirt
    - require:
      - group: libvirt-group
{% endfor %}

{# -------- Load KVM kernel modules (Intel/AMD tolerant) -------- #}
kvm-mod-base:
  cmd.run:
    - name: modprobe kvm || true
    - unless: lsmod | grep -q '^kvm'

kvm-mod-intel:
  cmd.run:
    - name: modprobe kvm_intel || true
    - unless: lsmod | grep -q '^kvm_intel'
    - onlyif: egrep -q '(vmx)' /proc/cpuinfo

kvm-mod-amd:
  cmd.run:
    - name: modprobe kvm_amd || true
    - unless: lsmod | grep -q '^kvm_amd'
    - onlyif: egrep -q '(svm)' /proc/cpuinfo

{# Persist modules across reboot #}
/etc/modules-load.d/kvm.conf:
  file.managed:
    - contents: |
        kvm
        kvm_intel
        kvm_amd

{# -------- Enable & start services -------- #}
libvirtd-service:
  service.running:
    - name: {{ libvirtd_service }}
    - enable: True
    - require:
      - pkg: kvm-deps

{% for svc in extra_services %}
{{ svc }}-service:
  service.running:
    - name: {{ svc }}
    - enable: True
    - require:
      - pkg: kvm-deps
{% endfor %}
