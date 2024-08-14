# Sidecar Performance Testing

## Sample Application Installation

Follow the [sample application installation](./istio-ambient-setup.md#sample-application-installation) section of
the Ambient setup guide to install the 3-tier test application.

## Baseline Performance Testing

Follow the [baseline performance testing](./istio-ambient-setup.md#baseline-performance-testing) section of
the Ambient setup guide to run the baseline performance test.

Uninstall the sample application after the performance testing is complete and reports have been generated:

```bash
kubectl delete -k tiered-app/$NUM-namespace-app/base
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

Set your Istio image environment variables:

```bash
REPO=docker.io/istio
ISTIO_IMAGE=1.22.1
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
meshConfig:
  accessLogFile: /dev/stdout
  enableAutoMtls: true
  defaultConfig:
    holdApplicationUntilProxyStarts: true
    proxyMetadata:
      ISTIO_META_DNS_CAPTURE: "true"
      ISTIO_META_DNS_AUTO_ALLOCATE: "true"
  outboundTrafficPolicy:
    mode: ALLOW_ANY
EOF
```

Wait for rollout to complete:

```bash
kubectl rollout status deploy/istiod -n istio-system
```

## Add the Sample Application to the Sidecar Mesh

Deploy the tiered app into sidecar mesh:

```bash
kubectl apply -k tiered-app/$NUM-namespace-app/sidecar
```

## Performance Testing

Scale down the load generator deployments:

```bash
for i in $(seq 1 $NUM); do
  kubectl scale deploy/vegeta1 -n ns-$i --replicas=0
  kubectl scale deploy/vegeta2 -n ns-$i --replicas=0
done
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
./scripts/run-all-reports.sh istio-sidecar-run-1
```

## Manual Performance Testing (Optional)

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
helm uninstall istiod -n istio-system
helm uninstall istio-base -n istio-system
```
