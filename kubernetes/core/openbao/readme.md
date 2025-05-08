# OpenBao

Fork of Open Source Hashicorp Vault

## Template

```bash
helm template openbao openbao/openbao \
  --namespace openbao \
  --create-namespace \
  --version 0.12.0 \
  --values kubernetes/core/openbao/values.yaml
```

## Install

```bash
helm repo add openbao https://openbao.github.io/openbao-helm
helm repo update

helm upgrade --install openbao openbao/openbao \
  --namespace openbao \
  --create-namespace \
  --version 0.12.0 \
  --values kubernetes/core/openbao/values.yaml
```
