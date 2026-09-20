# Archived TalHelper Configuration

This directory contains the deprecated [talhelper](https://github.com/budougumi0617/talhelper) configuration files that were previously used to manage Talos Linux cluster configuration for the `helo` cluster.

## Why Archived

TalHelper has been deprecated in favor of [TOPF](https://postfinance.github.io/topf/main/) (Talos Operating System Platform Framework). TOPF provides a more modern, composable approach to managing Talos cluster configurations.

## Migration

The active configuration has been migrated to TOPF. See `../topf/` for the current configuration structure.

The migration was completed on 2026-09-19. The TOPF configuration maintains the same cluster topology:

- **Cluster name**: `helo`
- **Control plane nodes**: segfault, cachecow, rampage
- **Worker nodes**: armstrong, intellectual, publicforum, quantumleap, zephyr, stackover
- **Talos version**: 1.13.2
- **Kubernetes version**: 1.36.1

## Files in This Archive

- `talconfig.yaml` — Original talhelper cluster configuration
- `talsecret.yaml` — Cluster secrets (plaintext)
- `patches/` — Talconfig patches by node type
- `clusterconfig/` — Generated per-node machine configurations

## References

- [talhelper GitHub Repository](https://github.com/budougumi0617/talhelper) — The deprecated tool
- [TOPF Documentation](https://postfinance.github.io/topf/main/) — The replacement framework
- [TOPF GitHub Repository](https://github.com/postfinance/topf) — TOPF source code

## Cleanup

These archived files can be safely removed after validating that the TOPF configuration works correctly. To clean up:

```bash
rm -rf archived-talhelper/
```
