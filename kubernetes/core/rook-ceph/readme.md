# Proxmox Commands

On the Proxmox host, run the following commands to generate

```bash
# Pull the script for Rook-Ceph 1.17
curl -s https://raw.githubusercontent.com/rook/rook/refs/heads/release-1.17/deploy/examples/create-external-cluster-resources.py > create-external-cluster-resources.py

# Run the script to generate the external cluster resource information
python3 create-external-cluster-resources.py \
--rbd-data-pool-name nvme \
--cephfs-filesystem-name cephfs \
--namespace rook-ceph \
--format bash

# NOTE: You may need to run `ceph mgr module enable prometheus` before
# running the script to enable the Prometheus module in Ceph.

# Make sure to set the permissions for the client.healthchecker user
ceph auth caps client.healthchecker \
mon 'allow r' osd 'allow r' mgr 'allow r'
```

Copy/paste the output into your local terminal.

Finally, we can install the Rook-Ceph cluster using Helm.

```bash
# Install Rook-Ceph using Helm
clusterNamespace=rook-ceph
operatorNamespace=rook-ceph

helm repo add rook-release https://charts.rook.io/release
helm repo update

helm upgrade --install --create-namespace \
--namespace $clusterNamespace rook-ceph rook-release/rook-ceph \
-f kubernetes/core/rook-ceph/values-external.yaml

helm upgrade --install --create-namespace \
--namespace $clusterNamespace rook-ceph-cluster \
--set operatorNamespace=$operatorNamespace rook-release/rook-ceph-cluster \
-f kubernetes/core/rook-ceph/values-external.yaml

# Add the CephFS Retain StorageClass
kubectl apply -f kubernetes/core/rook-ceph/cephfs-retain-sc.yaml
```
