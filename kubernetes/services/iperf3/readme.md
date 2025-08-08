# iperf3 Server

Quick way to run an iperf3 server in Kubernetes for networking tests.

```bash
helm template iperf3 --namespace iperf3 \
bjw-s/app-template --version 4.1.2 \
--values kubernetes/services/iperf3/values.yaml | \
kubectl apply -f-
```
