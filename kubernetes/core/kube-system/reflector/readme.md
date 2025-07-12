# emberstack/kubernetes-reflector

Installing [emberstack/kubernetes-reflector](https://github.com/emberstack/kubernetes-reflector) in the `kube-system` namespace.

```bash
helm repo add emberstack https://emberstack.github.io/helm-charts
helm repo update

helm upgrade --install reflector \
--namespace kube-system --version 9.1.21 \
emberstack/reflector
```
