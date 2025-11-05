# /srv/salt/kvm/manage.sls
# Manage VM lifecycle for win11-base

{% set vm_name = 'win11-base' %}
{% set action = salt['pillar.get']('action', 'status') %}

# Ensure VM definition exists (avoid accidental re-creation)
{{ vm_name }}-defined:
  cmd.run:
    - name: virsh dominfo {{ vm_name }} >/dev/null 2>&1 || echo "VM definition missing"
    - unless: virsh list --all | grep -q {{ vm_name }}

# Handle the action requested via pillar data
{% if action == 'start' %}
{{ vm_name }}-start:
  cmd.run:
    - name: virsh start {{ vm_name }}
    - unless: virsh list --state-running --name | grep -q {{ vm_name }}
    - require:
      - cmd: {{ vm_name }}-defined

{% elif action == 'stop' %}
{{ vm_name }}-stop:
  cmd.run:
    - name: virsh shutdown {{ vm_name }}
    - onlyif: virsh list --state-running --name | grep -q {{ vm_name }}
    - require:
      - cmd: {{ vm_name }}-defined

{% else %}
{{ vm_name }}-status:
  cmd.run:
    - name: |
        echo "--- VM Status ---"
        virsh dominfo {{ vm_name }} || echo "VM not defined"
        echo "-----------------"
    - require:
      - cmd: {{ vm_name }}-defined
{% endif %}

