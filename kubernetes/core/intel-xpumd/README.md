# intel-xpumd (Intel XPU Manager Daemon)

`xpumd` from [intel/xpumanager](https://github.com/intel/xpumanager) —
Intel's XPU monitoring daemon, deployed via the official OCI Helm chart
(`oci://ghcr.io/intel/xpumanager/charts`, chart `xpumd`) into namespace
`intel-xpu`.

Application: [`kubernetes/applications/intel-xpumd.yaml`](../../applications/intel-xpumd.yaml).
`automated.selfHeal: true` — pushes to `main` roll out automatically.

## What it does

Runs as a DaemonSet on the GPU node and collects Intel GPU metrics
(utilization, memory, power, temperature, frequency, health) through the
Level-Zero Sysman API. By default it only serves the local
`intel_xpu_info` exporter; here the **prometheus exporter** is enabled on
`:8080` and a `ServiceMonitor` (release label `monitoring`) is created, so
the in-cluster [Alloy](../k8s-monitoring/) scrapes it into Mimir.

## Why `gpuAccess: plugin`

The [Intel GPU device plugin](../intel-gpu/) (v0.36.0) runs with the
default **single** monitoring mode, which exposes one combined
`gpu.intel.com/monitoring` resource per node (the per-KMD
`gpu.intel.com/xe_monitoring` / `gpu.intel.com/i915_monitoring` resources
are 0). The chart's `gpuAccess` value must match what the node actually
offers, or the daemon pod stays Pending:

| `gpuAccess` | Resource requested | Usable here? |
|-------------|--------------------|--------------|
| `plugin`    | `gpu.intel.com/monitoring: 1` | **yes** (node allocates 1) |
| `xe`        | `gpu.intel.com/xe_monitoring: 1` | no (0 allocatable; needs plugin `--monitoring-mode=split`) |
| `dra`       | DRA claim | no (no DRA GPU resource driver in cluster) |

If the device plugin is ever switched to `--monitoring-mode=split`,
`gpuAccess` should be changed to `xe`.

## Why `kubernetes.io/hostname: intellectual`

The NFD label `intel.feature.node.kubernetes.io/gpu=true` (from the
plugin's node-feature-rules overlay) matches **8 nodes**, but only
`intellectual` has a discrete Intel GPU (ARC B70 PRO, PCI 0380-a780); the
others only expose CPU iGPUs (PCI 0300-xxxx). A daemon pod on those nodes
would run with a failing Sysman init and collect nothing.

## Grafana dashboards

`grafana.dashboards` is disabled — the cluster has no in-cluster Grafana
to load the dashboard ConfigMap. If one is added, enable it and point
`grafana.namespace` at the Grafana install.
