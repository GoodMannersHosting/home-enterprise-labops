# Self Hosted GitHub Action Runners

While we use the official helm chart for the controller, we **DO NOT** use the official chart for the runners during the deployment, as we're adding customizations after helm rendering. During upgrades or major changes, re-running and reconciling the rendered output is necessary.

```bash
helm template runner --namespace github \
oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
--version 0.13.1 \
--values kubernetes/services/github-action-runners/runners/values.yaml | code -
```
