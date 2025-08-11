# Rook Ceph Installation Guide

```bash
# Install Rook-Ceph using Helm
export clusterNamespace="rook-ceph"
export operatorNamespace="rook-ceph"
export rookcephVersion="v1.17.7"

helm repo add rook-release https://charts.rook.io/release
helm repo update

helm upgrade --install --create-namespace \
--namespace $clusterNamespace rook-ceph --version $rookcephVersion \
rook-release/rook-ceph -f kubernetes/core/rook-ceph/operator.values.yaml

helm upgrade --install --create-namespace \
--namespace $clusterNamespace --version $rookcephVersion \
rook-ceph-cluster --set operatorNamespace=$operatorNamespace \
rook-release/rook-ceph-cluster -f kubernetes/core/rook-ceph/cluster.values.yaml

# Finally, add the Retain StorageClass
kubectl apply -k kubernetes/core/rook-ceph
```
