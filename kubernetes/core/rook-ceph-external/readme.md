# Proxmox Commands

> [!CAUTION]
> This entire directory is deprecated and will be removed in the future. Please use the new [kubernetes/core/rook-ceph](../rook-ceph) directory instead.

On the Proxmox host, run the following commands to generate

```bash
# Pull the script for Rook-Ceph 1.17
curl -s https://raw.githubusercontent.com/rook/rook/refs/heads/release-1.17/deploy/examples/create-external-cluster-resources.py > create-external-cluster-resources.py

# Enable the Prometheus module in Ceph
ceph mgr module enable prometheus && sleep 30

# Run the script to generate the external cluster resource information
python3 create-external-cluster-resources.py \
--rbd-data-pool-name nvme \
--cephfs-filesystem-name cephfs \
--namespace rook-ceph \
--format bash

# Make sure to set the permissions for the client.healthchecker user
ceph auth caps client.healthchecker \
mon 'allow r' osd 'allow r' mgr 'allow r'
```

Now, copy/paste the output into your local terminal.

Finally, we can install the Rook-Ceph cluster using Helm.

```bash
# Install Rook-Ceph using Helm
export clusterNamespace="rook-ceph"
export operatorNamespace="rook-ceph"
export rookcephVersion="v1.17.6"

helm repo add rook-release https://charts.rook.io/release
helm repo update

helm upgrade --install --create-namespace \
--namespace $clusterNamespace rook-ceph --version $rookcephVersion \
rook-release/rook-ceph -f kubernetes/core/rook-ceph/values.yaml

helm upgrade --install --create-namespace \
--namespace $clusterNamespace --version $rookcephVersion \
rook-ceph-cluster --set operatorNamespace=$operatorNamespace \
rook-release/rook-ceph-cluster -f kubernetes/core/rook-ceph/cluster.values.yaml

# Once you import the variables from the python script, we can run this script to import and create the necessary resources:

curl -s https://raw.githubusercontent.com/rook/rook/refs/heads/release-1.17/deploy/examples/import-external-cluster.sh | bash

# Finally, add the CephFS Retain StorageClass
kubectl apply -k kubernetes/core/rook-ceph
```
