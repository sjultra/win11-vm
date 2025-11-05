{% set image_dir = "/var/lib/libvirt/images" %}
{% set images = {
  "win11": "Windows11.qcow2",
  "win11pro": "Windows11.qcow2"
} %}

# 1. Validate image directory
image-dir-check:
  file.directory:
    - name: {{ image_dir }}
    - user: root
    - group: root
    - mode: 0755
    - makedirs: True

# 2. Ensure image files exist
{% for name, file in images.items() %}
{{ name }}-image-check:
  file.exists:
    - name: {{ image_dir }}/{{ file }}
    - require:
      - file: image-dir-check

{{ name }}-image-perms:
  file.managed:
    - name: {{ image_dir }}/{{ file }}
    - user: qemu
    - group: qemu
    - mode: 0660
    - replace: False
    - require:
      - file: {{ name }}-image-check

{% endfor %}

# 3. Optional checksum verification (if pillar defines expected hashes)
{% for name, file in images.items() %}
{% if salt['pillar.get']('checksums:' ~ name) %}
{{ name }}-checksum-verify:
  cmd.run:
    - name: |
        expected="{{ salt['pillar.get']('checksums:' ~ name) }}"
        actual=$(sha256sum {{ image_dir }}/{{ file }} | awk '{print $1}')
        if [ "$expected" = "$actual" ]; then
          echo "PASS: {{ file }} checksum matches."
        else
          echo "FAIL: {{ file }} checksum mismatch!"
          exit 1
        fi
    - require:
      - file: {{ name }}-image-check
{% endif %}
{% endfor %}

# 4. Summary report
image-summary:
  cmd.run:
    - name: |
        echo "--- Windows Image Summary ---"
        for img in {{ ' '.join(images.values()) }}; do
          if [ -f "{{ image_dir }}/$img" ]; then
            echo "PASS: Found $img"
            ls -lh "{{ image_dir }}/$img"
          else
            echo "FAIL: Missing $img"
          fi
        done
        echo "--- End of Summary ---"
    - require:
      - file: image-dir-check

