# Hostname is already set on each node via installation.
# No need to set it in the machine config for existing nodes.
# If you need to override, use: talosctl set machine --hostname=<hostname>
---
apiVersion: v1alpha1
kind: HostnameConfig
auto: "off"
hostname: {{ .Node.Host }}
