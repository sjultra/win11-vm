virt:
  admin_users:
    - ops

  pkgs_override:
    RedHat:
      - qemu-kvm
      - libvirt
      - virt-install
      - swtpm
      - edk2-ovmf
    Debian:
      - qemu-kvm
      - libvirt-daemon-system
      - virtinst
      - swtpm
      - ovmf

