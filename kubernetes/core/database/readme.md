# Install CNPG

```bash
helm repo add cnpg https://cloudnative-pg.github.io/charts; helm repo update

helm upgrade --install cnpg cnpg/cloudnative-pg \
--namespace database --create-namespace --version 0.24.0

kubectl apply -k kubernetes/core/database
```
