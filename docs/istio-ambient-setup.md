# Ambient Performance Testing

## Sample Application Installation

Set the number of namespaces to use for testing:

```bash
NUM=25
```

Deploy the tiered app:

```bash
kubectl apply -k tiered-app/$NUM-namespace-app/base
```

Wait for the tiered app rollout to complete:

```bash
for i in $(seq 1 $NUM); do
  kubectl rollout status deploy/tier-1-app-a -n ns-$i
  kubectl rollout status deploy/tier-1-app-b -n ns-$i
  kubectl rollout status deploy/tier-2-app-a -n ns-$i
  kubectl rollout status deploy/tier-2-app-b -n ns-$i
  kubectl rollout status deploy/tier-2-app-c -n ns-$i
  kubectl rollout status deploy/tier-2-app-d -n ns-$i
  kubectl rollout status deploy/tier-3-app-a -n ns-$i
  kubectl rollout status deploy/tier-3-app-b -n ns-$i
done
```

## Baseline Performance Testing

Deploy the Vegeta load generators:

```bash
kubectl apply -k loadgenerators/$NUM-loadgenerators/base
```

Wait for the load generator rollouts to complete:

```bash
for i in $(seq 1 $NUM); do
  kubectl rollout status deploy/vegeta1 -n ns-$i
  kubectl rollout status deploy/vegeta2 -n ns-$i
done
```

Tail the vegeta load generator logs until you see the following (10-minutes):

```bash
$ kubectl logs -l app=vegeta1 -f -n ns-1
Requests      [total, rate, throughput]         120000, 200.00, 200.00
Duration      [total, attack, wait]             10m0s, 10m0s, 1.942ms
Latencies     [min, mean, 50, 90, 95, 99, max]  1.63ms, 1.919ms, 1.899ms, 2.033ms, 2.115ms, 2.374ms, 25.578ms
Bytes In      [total, mean]                     325486616, 2712.39
Bytes Out     [total, mean]                     0, 0.00
Success       [ratio]                           100.00%
Status Codes  [code:count]                      200:120000
Error Set:
```

Generate the reports:

```bash
./scripts/run-all-reports.sh ambient-baseline-run-1
```

`ambient-baseline-run-1` is the prefix applied to the performance report filenames stored in the `out` directory.

Scale down the load generator deployments:

```bash
for i in $(seq 1 $NUM); do
  kubectl scale deploy/vegeta1 -n ns-$i --replicas=0
  kubectl scale deploy/vegeta2 -n ns-$i --replicas=0
done
```

## Istio Installation

Add Istio helm repo:

```bash
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
```

Install istio-base:

```bash
helm upgrade --install istio-base istio/base -n istio-system --version 1.22.1 --create-namespace
```

On GKE, Istio components with the system-node-critical priorityClassName can only be installed in
namespaces that have a ResourceQuota defined:

```bash
kubectl -n istio-system apply -f - <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: gcp-critical-pods
  namespace: istio-system
spec:
  hard:
    pods: 1000
  scopeSelector:
    matchExpressions:
    - operator: In
      scopeName: PriorityClass
      values:
      - system-node-critical
EOF
```

Install Kubernetes Gateway CRDs:

```bash
kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || \
  { kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v1.0.0" | kubectl apply -f -; }
```

Set your Istio image environment variables:

```bash
REPO=docker.io/istio
ISTIO_IMAGE=1.22.1
```

Install istio-cni:

```bash
helm upgrade --install istio-cni istio/cni \
-n istio-system \
--version=1.22.1 \
-f -<<EOF
global:
  hub: $REPO
  tag: $ISTIO_IMAGE
profile: ambient
EOF
```

Wait for rollout to complete:

```bash
kubectl rollout status ds/istio-cni-node -n istio-system
```

Install Istiod:

```bash
helm upgrade --install istiod istio/istiod \
-n istio-system \
--version=1.22.1 \
-f -<<EOF
global:
  hub: $REPO
  tag: $ISTIO_IMAGE
profile: ambient
EOF
```

Wait for rollout to complete:

```bash
kubectl rollout status deploy/istiod -n istio-system
```

Configure a waypoint proxy per namespace. First, add waypoint pod anti-affinity to the
sidecar ConfigMap `waypoint.deployment.spec.template.spec`:

```bash
              affinity:
                podAntiAffinity:
                  preferredDuringSchedulingIgnoredDuringExecution:
                  - weight: 100
                    podAffinityTerm:
                      labelSelector:
                        matchExpressions:
                        - key: service.istio.io/canonical-name
                          operator: In
                          values:
                          - waypoint
                      namespaceSelector: {}
                      topologyKey: "kubernetes.io/hostname"
```

TODO: Make waypoints configurable at install time: https://github.com/istio/istio/pull/51505

Install ztunnel:

```bash
helm upgrade --install ztunnel istio/ztunnel \
-n istio-system \
--version=1.22.1 \
-f -<<EOF
variant: distroless
hub: $REPO
tag: $ISTIO_IMAGE
EOF
```

__Note:__ Use `kubectl port-forward -n istio-system ds/ztunnel 15020:15020` to access the ztunnel metrics API
after running an ambient performance test. L7 metrics such as `total requests` and `duration` with labels that
are based on the L7 attributes (e.g. `Result Code`) should be observed. For example:

```bash
...
istio_requests_total{response_code="200",reporter="source",source_workload="tier-1-app-a",source_canonical_service="tier-1-app-a",source_canonical_revision="latest",source_workload_namespace="ns-5",source_principal="spiffe://cluster.local/ns/ns-5/sa/tier-1-app-a",source_app="tier-1-app-a",source_version="latest",source_cluster="Kubernetes",destination_service="tier-2-app-b.ns-5.svc.cluster.local",destination_service_namespace="ns-5",destination_service_name="tier-2-app-b",destination_workload="tier-2-app-b",destination_canonical_service="tier-2-app-b",destination_canonical_revision="latest",destination_workload_namespace="ns-5",destination_principal="spiffe://cluster.local/ns/ns-5/sa/tier-2-app-b",destination_app="tier-2-app-b",destination_version="latest",destination_cluster="Kubernetes",request_protocol="http",response_flags="-",connection_security_policy="mutual_tls"} 376752
```

Wait for rollout to complete:

```bash
kubectl rollout status ds/ztunnel -n istio-system
```

## Add the Sample Application to the Ambient Mesh

Deploy the tiered app into ambient mesh:

```bash
kubectl apply -k tiered-app/$NUM-namespace-app/ambient
```

## Ambient mTLS Performance Testing

Scale up the load generator deployments:

```bash
for i in $(seq 1 $NUM); do
  kubectl scale deploy/vegeta1 -n ns-$i --replicas=1
  kubectl scale deploy/vegeta2 -n ns-$i --replicas=1
done
```

Wait for the load generator rollouts to complete:

```bash
for i in $(seq 1 $NUM); do
  kubectl rollout status deploy/vegeta1 -n ns-$i
  kubectl rollout status deploy/vegeta2 -n ns-$i
done
```

Tail the vegeta load generator logs until you see the following (10-minutes):

```bash
$ kubectl logs -l app=vegeta1 -f -n ns-1
Requests      [total, rate, throughput]         120000, 200.00, 200.00
Duration      [total, attack, wait]             10m0s, 10m0s, 1.942ms
Latencies     [min, mean, 50, 90, 95, 99, max]  1.63ms, 1.919ms, 1.899ms, 2.033ms, 2.115ms, 2.374ms, 25.578ms
Bytes In      [total, mean]                     325486616, 2712.39
Bytes Out     [total, mean]                     0, 0.00
Success       [ratio]                           100.00%
Status Codes  [code:count]                      200:120000
Error Set:
```

Generate the test reports:

```bash
./scripts/run-all-reports.sh ambient-mtls-run-1
```

Scale down the load generator deployments:

```bash
for i in $(seq 1 $NUM); do
  kubectl scale deploy/vegeta1 -n ns-$i --replicas=0
  kubectl scale deploy/vegeta2 -n ns-$i --replicas=0
done
```

## L4 Auth Performance Testing

Configure l4 auth policy:

```bash
kubectl apply -k tiered-app/$NUM-namespace-app/ambient/l4-policy
```

Scale up the load generator deployments:

```bash
for i in $(seq 1 $NUM); do
  kubectl scale deploy/vegeta1 -n ns-$i --replicas=1
  kubectl scale deploy/vegeta2 -n ns-$i --replicas=1
done
```

Wait for the load generator rollouts to complete:

```bash
for i in $(seq 1 $NUM); do
  kubectl rollout status deploy/vegeta1 -n ns-$i
  kubectl rollout status deploy/vegeta2 -n ns-$i
done
```

Tail the vegeta load generator logs until you see the following (10-minutes):

```bash
$ kubectl logs -l app=vegeta1 -f -n ns-1
Requests      [total, rate, throughput]         120000, 200.00, 200.00
Duration      [total, attack, wait]             10m0s, 10m0s, 1.942ms
Latencies     [min, mean, 50, 90, 95, 99, max]  1.63ms, 1.919ms, 1.899ms, 2.033ms, 2.115ms, 2.374ms, 25.578ms
Bytes In      [total, mean]                     325486616, 2712.39
Bytes Out     [total, mean]                     0, 0.00
Success       [ratio]                           100.00%
Status Codes  [code:count]                      200:120000
Error Set:
```

Generate the test reports:

```bash
./scripts/run-all-reports.sh ambient-l4-auth-run-1
```

Scale down the load generator deployments:

```bash
for i in $(seq 1 $NUM); do
  kubectl scale deploy/vegeta1 -n ns-$i --replicas=0
  kubectl scale deploy/vegeta2 -n ns-$i --replicas=0
done
```

## L7 Auth Performance Testing

Deploy the waypoint proxies:

```bash
kubectl apply -k tiered-app/$NUM-namespace-app/ambient/waypoints
```

Wait for the waypoint rollouts to complete:

```bash
for i in $(seq 1 $NUM); do
  kubectl rollout status deploy/waypoint -n ns-$i
done
```

Configure l7 auth policy:

```bash
kubectl apply -k tiered-app/$NUM-namespace-app/ambient/l7-policy
```

Scale up the load generator deployments:

```bash
for i in $(seq 1 $NUM); do
  kubectl scale deploy/vegeta-ns-$i -n ns-$i --replicas=1
done
```

Wait for the load generator rollouts to complete:

```bash
for i in $(seq 1 $NUM); do
  kubectl rollout status deploy/vegeta-ns-$i -n ns-$i
done
```

Tail the vegeta load generator logs until you see the following (10-minutes):

```bash
$ kubectl logs -l app=vegeta1 -f -n ns-1
Requests      [total, rate, throughput]         120000, 200.00, 200.00
Duration      [total, attack, wait]             10m0s, 10m0s, 1.942ms
Latencies     [min, mean, 50, 90, 95, 99, max]  1.63ms, 1.919ms, 1.899ms, 2.033ms, 2.115ms, 2.374ms, 25.578ms
Bytes In      [total, mean]                     325486616, 2712.39
Bytes Out     [total, mean]                     0, 0.00
Success       [ratio]                           100.00%
Status Codes  [code:count]                      200:120000
Error Set:
```

Generate the test reports:

```bash
./scripts/run-all-reports.sh ambient-l7-auth-run-1
```

## Manual Testing (Optional)

Example exec into vegeta to run your own test:

```bash
kubectl --namespace ns-1 exec -it deploy/vegeta-ns-1 -c vegeta -- /bin/sh
```

Example test run:

```bash
echo "GET http://tier-1-app-a.ns-1.svc.cluster.local:8080" | vegeta attack -dns-ttl=0 -rate 500/1s -duration=2s | tee results.bin | vegeta report -type=text

echo "GET http://tier-1-app-a.ns-5.svc.cluster.local:8080" | vegeta attack -dns-ttl=0 -rate 500/1s -duration=2s | tee results.bin | vegeta report -type=text

echo "GET http://tier-1-app-a.ns-6.svc.cluster.local:8080" | vegeta attack -dns-ttl=0 -rate 500/1s -duration=2s | tee results.bin | vegeta report -type=text

echo "GET http://tier-1-app-a.ns-10.svc.cluster.local:8080" | vegeta attack -dns-ttl=0 -rate 500/1s -duration=2s | tee results.bin | vegeta report -type=text

echo "GET http://tier-1-app-a.ns-11.svc.cluster.local:8080" | vegeta attack -dns-ttl=0 -rate 500/1s -duration=2s | tee results.bin | vegeta report -type=text

echo "GET http://tier-1-app-a.ns-20.svc.cluster.local:8080" | vegeta attack -dns-ttl=0 -rate 500/1s -duration=2s | tee results.bin | vegeta report -type=text
```

## Optional Commands

Verify that the tiered app was not scheduled to the load generator nodes:

```bash
kubectl get po -A -o wide | grep tier | grep $NODE1
```

__Note:__ Repeat the above step for each load generator node.

Scale down the tiered app deployments:

```bash
for i in $(seq 1 $NUM); do
  kubectl scale deploy/tier-1-app-a -n ns-$i --replicas=0
  kubectl scale deploy/tier-1-app-b -n ns-$i --replicas=0
  kubectl scale deploy/tier-2-app-a -n ns-$i --replicas=0
  kubectl scale deploy/tier-2-app-b -n ns-$i --replicas=0
  kubectl scale deploy/tier-2-app-c -n ns-$i --replicas=0
  kubectl scale deploy/tier-2-app-d -n ns-$i --replicas=0
  kubectl scale deploy/tier-3-app-a -n ns-$i --replicas=0
  kubectl scale deploy/tier-3-app-b -n ns-$i --replicas=0
done
```

Scale up the tiered app deployments:

```bash
for i in $(seq 1 $NUM); do
  kubectl scale deploy/tier-1-app-a -n ns-$i --replicas=1
  kubectl scale deploy/tier-1-app-b -n ns-$i --replicas=1
  kubectl scale deploy/tier-2-app-a -n ns-$i --replicas=1
  kubectl scale deploy/tier-2-app-b -n ns-$i --replicas=1
  kubectl scale deploy/tier-2-app-c -n ns-$i --replicas=1
  kubectl scale deploy/tier-2-app-d -n ns-$i --replicas=1
  kubectl scale deploy/tier-3-app-a -n ns-$i --replicas=1
  kubectl scale deploy/tier-3-app-b -n ns-$i --replicas=1
done
```

## Addons Installation (Optional)

Deploy sample addons:

```bash
kubectl apply -k addons
```

Port forward to Grafana:

```bash
kubectl port-forward svc/grafana -n istio-system 3000:3000
```

Port forward to Kiali:

```bash
kubectl port-forward svc/kiali -n istio-system 20001:20001
```

## Cleanup

When testing is complete, uninstall Istio:

```bash
helm uninstall ztunnel -n istio-system
helm uninstall istiod -n istio-system
helm uninstall istio-cni -n istio-system
helm uninstall istio-base -n istio-system
kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v1.0.0" | kubectl delete -f -;
```
