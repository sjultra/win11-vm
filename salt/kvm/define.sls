win11-base-xml:
  file.managed:
    - name: /etc/libvirt/qemu/win11-base.xml
    - source: salt://kvm/templates/win11-base.xml
    - mode: '0644'
    - user: root
    - group: root

win11-base-define:
  cmd.run:
    - name: virsh define /etc/libvirt/qemu/win11-base.xml
    - unless: virsh list --all | grep -q 'win11-base'
    - require:
      - file: win11-base-xml

verify-vm-registered:
  cmd.run:
    - name: virsh list --all
    - require:
      - cmd: win11-base-define

