# Manualy Deployment of LibreChat on Kubernetes

GitHub Repo: [danny-avila/LibreChat](https://github.com/danny-avila/LibreChat)

> [!NOTE]
> I decided not to go with this tool, as I personally found it less user friendly compared to Open WebUI. However, for those interested in deploying LibreChat on Kubernetes, the following instructions can be followed.

## Deployment

```bash
# Deploy the configmap and secret
kubectl apply -k kubernetes/services/librechat

# Add Helm Repositories
helm repo add otwld https://helm.otwld.com/
helm repo add bjw-s https://bjw-s-labs.github.io/helm-charts
helm repo update

# Deploy the two Helm charts
## Deploy the Ollama Embeddings Service
helm template embeddings --namespace aiml \
otwld/ollama --version 1.32.0 \
--values kubernetes/services/librechat/embeddings-ollama.values.yaml | \
k apply -f-

## LibreChat - we're running sed for Gateway API compatibility
helm template librechat --namespace aiml \
bjw-s/app-template --version 4.4.0 \
--values kubernetes/services/librechat/values.yaml | \
sed 's/v1alpha2/v1/g' | k apply -f-
```
