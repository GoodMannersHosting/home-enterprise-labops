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

## Re-Installing Rook-Ceph

If something goes wrong and you need to re-install Rook-Ceph, you can follow these steps:

1. Delete the Rook-Ceph Cluster and BlockPool
2. Patch out the finalizers on the blookpool resource
3. Wait for everything to be deleted
4. Open a debug shell on each node and wipe the disks

```bash
for node in $(k get nodes -ojsonpath='{.items[*].metadata.name}'); do
    kubectl -n kube-system debug node/${node} --image ubuntu --profile sysadmin -it
done

# For each of the nodes, run the command below
# CRITICAL CRITICAL CRITICAL CRITICAL WARNING: Make sure you know EXACTLY which disks you are nuking!
# This will wipe the disks and remove all data on them.
DISKS="space separated list of disks to nuke"
apt update && apt install -y fdisk gdisk parted -y
for disk in ${DISKS}; do
    DISK="/dev/$disk"
    sgdisk --zap-all $DISK
    dd if=/dev/zero of="$DISK" bs=1K count=200 oflag=direct,dsync seek=0 # Clear at offset 0
    dd if=/dev/zero of="$DISK" bs=1K count=200 oflag=direct,dsync seek=$((1 * 1024**2)) # Clear at offset 1GB
    dd if=/dev/zero of="$DISK" bs=1K count=200 oflag=direct,dsync seek=$((10 * 1024**2)) # Clear at offset 10GB
    dd if=/dev/zero of="$DISK" bs=1K count=200 oflag=direct,dsync seek=$((100 * 1024**2)) # Clear at offset 100GB
    dd if=/dev/zero of="$DISK" bs=1K count=200 oflag=direct,dsync seek=$((1000 * 1024**2)) # Clear at offset 1000GB
    partprobe $DISK;
done
```

Finally, reboot the nodes.

```bash
talosctl --talosconfig=./clusterconfig/talosconfig reboot -n=172.21.0.1{5..8}
```

Then, we can go ahead and re-install Rook-Ceph using the commands provided above.
