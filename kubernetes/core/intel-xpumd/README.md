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
`:8080` and a `Service` is created (`service.create: true`), so the in-cluster
[Alloy](../k8s-monitoring/) can scrape it into Mimir.

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

## Namespace PSA labels

The namespace carries `pod-security.kubernetes.io/{enforce,audit,warn}:
privileged` (see `namespace.yaml`). The Talos cluster enables a
cluster-wide PodSecurity admission default of **baseline** for unlabeled
namespaces (only `kube-system` is exempt), and baseline rejects the
`PERFMON` capability and hostPath volumes this daemon needs — without the
label, pod creation fails and the DaemonSet stays at 0/1.

## Why the ServiceMonitor lives in this directory

The chart's own `ServiceMonitor` template (`templates/servicemonitor.yaml`,
xpumd 2.2.0) hardcodes `interval: 5s` with **no** `scrapeTimeout`, and the
chart exposes no value to set either. The in-cluster `alloy-metrics`
collector fills a missing `scrapeTimeout` with its `global.scrapeTimeout`
default of `10s` (see [../k8s-monitoring/values.yaml](../k8s-monitoring/values.yaml));
`10s > 5s` is an invalid scrape config, so `alloy-metrics` drops the ServiceMonitor
and no `intel-xpu` targets are scraped (its logs show
`error generating scrapeconfig from serviceMonitor ... scrape timeout greater
than scrape interval`).

`prometheus.monitor: false` in [values.yaml](values.yaml) disables the chart's
broken `ServiceMonitor`, and [servicemonitor.yaml](servicemonitor.yaml) ships a
replacement with an explicit `scrapeTimeout: 4s` (`<= interval: 5s`) so the
scrape config is valid. If the chart ever gains `scrapeTimeout`/`interval`
values (or raises the hardcoded interval to `>= 10s`), the chart's
`ServiceMonitor` can be re-enabled and this file removed.

## Grafana dashboards

`grafana.dashboards` is disabled — the cluster has no in-cluster Grafana
to load the dashboard ConfigMap. If one is added, enable it and point
`grafana.namespace` at the Grafana install.

[`grafana-dashboard.json`](grafana-dashboard.json) is the upstream
dashboard ([`json/dashboard.json`](https://github.com/intel/xpumanager/blob/main/xpumd/charts/xpumd/json/dashboard.json),
Grafana v12 Dashboard API format) converted to the classic copy/paste
dashboard model (`schemaVersion 39`) — paste it into Grafana's
*Import dashboard* JSON box. It expects a Prometheus datasource variable
named `Metrics` (preselected: `Prometheus`) and a `node` label from
`hw_gpu_info`, which the xpumd prometheus exporter provides.
