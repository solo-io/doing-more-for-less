# Create a GKE Cluster

Set the following variables for cluster name, zone, machine type, number of nodes, k8s version, and the target GKE project:

```bash
GKE_CLUSTER_NAME="danehans-gke-cluster"
GKE_CLUSTER_ZONE="us-west4-b"
MAIN_MACHINE_TYPE="n2-standard-8"
MAIN_NUM_NODES="25"
GKE_PROJECT="solo-oss"
CLUSTER_VERSION="1.29.6-gke.1038001"
LABEL="user=danehans"
```

## Node Requirements

- 25 total nodes (21 workload and 4 loadgen) for all test cases other than Istio sidecar.
- 27 total nodes (23 workload and 4 loadgen) for L7 auth with 50 waypoints.

## Create Cluster

Create the cluster. Omit the `--spot` flag if you do not want to use spot instances:

```bash
gcloud container clusters create ${GKE_CLUSTER_NAME} \
  --cluster-version ${CLUSTER_VERSION} \
  --no-enable-autoupgrade \
  --machine-type=${MAIN_MACHINE_TYPE} \
  --num-nodes ${MAIN_NUM_NODES} \
  --zone ${GKE_CLUSTER_ZONE} \
  --project ${GKE_PROJECT} \
  --logging NONE \
  --no-enable-autoscaling \
  --labels=${LABEL}
```

__Notes:__

- Add the `--node-taints node.cilium.io/agent-not-ready=true:NoExecute` flag when creating the cluster.
- Add `--spot` to use GKE spot instances.

## Taint Load Generator Nodes

Label nodes that will run the Vegeta load generator:

```bash
# Use 4 nodes for 25/30-ns, 5 nodes for 50-ns
NODE1=gke-gke-ambient-danehans-default-pool-43b8fead-0hs3
NODE2=gke-gke-ambient-danehans-default-pool-43b8fead-0jmr
NODE3=gke-gke-ambient-danehans-default-pool-43b8fead-1fht
NODE4=gke-gke-ambient-danehans-default-pool-43b8fead-32pn
NODE5=gke-gke-ambient-danehans-default-pool-43b8fead-4vkl
kubectl label node/$NODE1 node/$NODE2 node/$NODE3 node/$NODE4 node=loadgen
```

Taint the load generator nodes:

```bash
for node in $(kubectl get nodes -l node=loadgen -o name); do
  kubectl taint nodes $node loadgen=true:NoSchedule
done
```

__Note:__ The Vegeta deployment will add a toleration to the load generator pods.

## Node Pool Resizing (Optional)

If you want to scale down a particular node pool, in this case the `default-pool`:

```bash
gcloud container clusters resize ${GKE_CLUSTER_NAME} --zone ${GKE_CLUSTER_ZONE} --num-nodes 0 --node-pool default-pool
```

## Cleanup

Run the following command to delete the cluster:

```bash
gcloud container clusters delete ${GKE_CLUSTER_NAME} --zone ${GKE_CLUSTER_ZONE} --project ${GKE_PROJECT}
```
