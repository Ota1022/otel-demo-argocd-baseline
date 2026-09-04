# OpenTelemetry Demo on kind, managed by Argo CD

Baseline environment for comparing, later, two ways of shipping the same telemetry to AWS:

- upstream OpenTelemetry Collector -> CloudWatch
- CloudWatch Agent -> CloudWatch

This repository only builds the common ground: the official OpenTelemetry Demo (Astronomy Shop)
on a local kind cluster, deployed and drift-checked by Argo CD, with the demo's own local backends
(Jaeger, Prometheus, Grafana, OpenSearch). **No AWS resources are created.** The comparison plan lives in
[experiments/README.md](experiments/README.md).

## Verification status

| Step | Status |
|---|---|
| Tool versions, chart version, chart defaults, official docs | checked on this Mac, 2026-09-04 14:10 JST |
| Local render: `helm template` (Helm 4.0.5) of chart 0.41.0 with `otel-demo/values/local.yaml` | checked 2026-09-04: 92 objects render; the comment-only values file is accepted |
| kind cluster | executed 2026-09-04: node `NotReady` for about 20 s (kindnet starting), `Ready` after about 35 s; kube-system has 8 pods |
| Argo CD install | executed 2026-09-04: client-side apply created only 2 of 3 CRDs (`applicationsets.argoproj.io` hit the 262,144-byte annotation limit) and `argocd-applicationset-controller` crash-looped; re-applying with `--server-side` created the missing CRD and all 7 pods became `Running`; the script now uses `--server-side` (see Setup step 2) |
| First Sync | executed 2026-09-04: `argocd app sync` applied 92 objects in 3 s. The Grafana dashboard ConfigMap did **not** hit the annotation limit (236,779 bytes as JSON), so `ServerSideApply` is not needed. Starting all 30 pods saturated the VM for about 30 minutes (node load average above 100, Mac swapping 5 GB, kube-apiserver / etcd / CoreDNS / `argocd-repo-server` restarting on failed liveness probes). agent, mcp, chatbot, telemetry-docs and load-generator were then disabled in `local.yaml` (commit 248cd08) and pruned. Result: 82 objects, 25 pods, Synced / Healthy |
| Trace check, GitOps / drift demo | **not yet executed** — steps below come from the official docs and the chart contents; update this table and the notes when you run them |

## Architecture

```text
 Git (this repo)                    Helm repo (open-telemetry.github.io)
   otel-demo/values/local.yaml        opentelemetry-demo 0.41.0
          \                              /
           \   source 2 ($values)       /  source 1 (chart, version pinned)
            v                          v
        +---------------------------------+
        | Argo CD (namespace: argocd)     |  renders the chart with its bundled Helm 4.2.1,
        | Application "otel-demo"         |  compares desired vs live, syncs on request
        +---------------------------------+
                        |
                        v
        +---------------------------------------------------------------+
        | kind cluster "otel-demo" (1 node, Kubernetes v1.35.0)         |
        |                                                               |
        |  namespace otel-demo                                          |
        |   frontend-proxy (Envoy) -> frontend -> checkout, cart, ...   |
        |        |                       |                              |
        |        | /otlp-http/           | OTLP gRPC 4317 / HTTP 4318   |
        |        v                       v                              |
        |   otel-collector (DaemonSet, opentelemetry-collector-contrib) |
        |        | traces          | metrics            | logs          |
        |        v                 v                    v               |
        |     jaeger          prometheus            opensearch          |
        |        \                 |                    /               |
        |         +------------ grafana ---------------+                |
        +---------------------------------------------------------------+
                        ^
                        | kubectl port-forward
                  Mac: localhost:8080 (shop, Jaeger, Grafana), localhost:8443 (Argo CD)
```

## Prerequisites

Checked on macOS 26.6.2 (Apple Silicon, 16 GiB RAM, 10 CPU) on 2026-09-04.

| Tool | Version used | Notes |
|---|---|---|
| Docker | client 29.1.4-rd / server 29.5.3 | Rancher Desktop, container engine `moby`, Rancher Desktop's own Kubernetes disabled |
| kind | v0.31.0 | node image pinned by digest in [kind/cluster.yaml](kind/cluster.yaml) (`kindest/node:v1.35.0`) |
| kubectl | via kuberlr (`~/.rd/bin/kubectl`) | downloads a kubectl matching the server minor version on first use |
| Helm | v4.0.5 | optional on the Mac; only for `helm show values` / `helm template`. Argo CD renders with its own Helm |
| argocd CLI | v3.5.2 | optional; the same operations are available in the Argo CD web UI |
| gh / git | any recent | the values repo must be reachable by Argo CD without credentials, so it is public |

Memory: the Rancher Desktop VM is set to **10 GB RAM / 6 CPU** (`rdctl set --virtual-machine.memory-in-gb 10 --virtual-machine.number-cpus 6`).
Reasoning: the sum of memory limits of all enabled components in chart 0.41.0 is about 8.3 GiB
(apps 4182Mi + dependencies 1310Mi + observability 3056Mi), actual usage is below limits, and kind + Argo CD need roughly another 1–1.5 GiB.

Official requirements vs the chart itself (2026-09-04):

| Source | Says |
|---|---|
| opentelemetry.io/docs/demo/kubernetes-deployment/ | Kubernetes 1.24+, Helm 3.14+, 6 GB free RAM for the application |
| opentelemetry.io/docs/demo/docker-deployment/ | 6 GB RAM (about 3 GB in minimal mode), 14 GB disk |
| chart 0.41.0 README (`helm show readme`) | Kubernetes 1.24+, **Helm 4.0+** |
| Argo CD v3.5.2 `hack/tool-versions.sh` | bundles Helm 4.2.1 |

The docs and the chart disagree on Helm; the chart wins. Both the local Helm 4.0.5 and Argo CD's Helm 4.2.1 satisfy it.

## Chart version

`opentelemetry-demo` **0.41.0** (appVersion 3.0.0), pinned in [argocd/application.yaml](argocd/application.yaml).

`helm search repo open-telemetry/opentelemetry-demo --versions` on 2026-09-04 14:10 JST:

| chart | appVersion | published |
|---|---|---|
| 0.41.0 | 3.0.0 | 2026-07-30 |
| 0.40.10 | 2.2.0 | 2026-07-16 |

Reason: latest at the time of checking and the only chart for demo release 3.0.0 (2026-07-24).
The version is pinned, not "latest", so the AWS comparison later runs against exactly the same demo.
Sub-charts: opentelemetry-collector 0.165.0, jaeger 4.11.1, prometheus 29.18.0, grafana 12.7.2, opensearch 3.7.0.

Notable 3.0.0 changes (from the GitHub release notes): custom attributes renamed from `app.*` to `demo.*`;
new `agent`, `mcp`, `chatbot` services; load generator switched from Locust to k6;
`product-reviews`, `llm`, Tracetest removed; checkout and shipping now export OTLP over http/protobuf.

## How Helm and Git are combined

Argo CD **multiple sources**: source 1 is the official Helm repository with the chart version pinned;
source 2 is this repository, referenced as `$values`, providing only the values file.
The upstream chart is not copied. Switching a comparison condition means adding one values file and changing one line
(`valueFiles`) in the Application.

Alternatives not taken:

- Umbrella chart in Git (a `Chart.yaml` depending on the upstream chart): values move one level deeper
  (`opentelemetry-demo:`), so they no longer line up with `helm show values`; adds a chart layer of our own.
- Inline `helm.valuesObject` in the Application: single source, but each condition would need a copy of the
  Application with a duplicated values block, which hides the actual diff.

Argo CD constraints: a source with `ref` cannot also have `chart`; `$values` resolves to the root of that repo.

## Repository layout

```text
.
├── README.md                    # this file
├── kind/cluster.yaml            # kind cluster, node image pinned by digest
├── argocd/application.yaml      # Argo CD Application (multiple sources)
├── otel-demo/values/local.yaml  # local baseline values: only diffs from upstream defaults
├── experiments/README.md        # plan for the CloudWatch comparison (not implemented)
├── baseline/                    # recorded traces from the local backend
└── scripts/
    ├── bootstrap-kind.sh        # kind create cluster
    ├── bootstrap-argocd.sh      # kubectl apply of the pinned Argo CD install.yaml
    ├── port-forward.sh          # frontend-proxy 8080 + argocd-server 8443
    └── cleanup.sh               # kind delete cluster
```

## Setup

All commands run from the repository root.

1. **kind cluster**

   ```bash
   ./scripts/bootstrap-kind.sh
   ```

   Pulls `kindest/node:v1.35.0`, starts one Docker container `otel-demo-control-plane` as the node,
   adds kubeconfig context `kind-otel-demo`. Check: `kubectl get nodes` shows `Ready`.

2. **Argo CD**

   ```bash
   ./scripts/bootstrap-argocd.sh
   ```

   Creates namespace `argocd` and applies the official Argo CD v3.5.2 `install.yaml`
   (3 CRDs, RBAC, 6 Deployments, 1 StatefulSet, Services) with **server-side apply**. This is the only deployment done with kubectl.
   Check: `kubectl -n argocd get pods` shows 7 pods `Running`. The script prints the initial `admin` password.

   Why `--server-side` (observed 2026-09-04): client-side apply stores every object again in the
   `kubectl.kubernetes.io/last-applied-configuration` annotation, limited to 262,144 bytes. The `applicationsets.argoproj.io`
   CRD is 1,394,816 bytes as YAML and fails with `metadata.annotations: Too long`; kubectl keeps applying the remaining objects
   and exits 1, so the script stopped after the apply with only 2 of 3 CRDs created and `argocd-applicationset-controller`
   in CrashLoopBackOff (`no matches for kind "ApplicationSet"`). The `applications.argoproj.io` CRD (405,969 bytes as YAML,
   197,612 as the compact JSON stored in the annotation) still fits. Recovery from that state: run the same apply with
   `--server-side`; existing objects are unchanged and the missing CRD is created.

3. **Application bootstrap (one-time kubectl apply)**

   ```bash
   kubectl apply -f argocd/application.yaml
   argocd app get otel-demo        # or open the web UI
   ```

   Argo CD fetches chart 0.41.0 and `otel-demo/values/local.yaml`, renders the manifests, and reports
   **OutOfSync / Missing**: nothing is deployed yet because `automated` sync is intentionally off.

   To read the rendered manifests (including the effective Collector config):

   ```bash
   argocd app manifests otel-demo | awk '/name: otel-collector$/,0' | head -200
   ```

4. **First Sync**

   ```bash
   argocd app sync otel-demo                                 # or SYNC -> SYNCHRONIZE in the UI
   kubectl -n otel-demo get pods -w                          # watch in another terminal
   argocd app wait otel-demo --sync --health --timeout 1200
   ```

   About 25 images are pulled the first time; expect several minutes. Done when `argocd app get otel-demo`
   shows **Synced / Healthy**.

   If Sync fails with `ConfigMap ... metadata.annotations: Too long` (large Grafana dashboards),
   add `ServerSideApply=true` to `syncPolicy.syncOptions`, commit, push, `argocd app get otel-demo --refresh`, Sync again,
   and record here that it was needed. This is plausible: the largest rendered object, ConfigMap
   `grafana-dashboard-opentelemetry-collector`, is 236,765 bytes as YAML (local `helm template`, 2026-09-04), and client-side
   apply stores the whole object again in the `last-applied-configuration` annotation, whose limit is 262,144 bytes.

## Access

```bash
./scripts/port-forward.sh
```

| UI | URL | Notes |
|---|---|---|
| Astronomy Shop | http://localhost:8080/ | port must be 8080: the browser posts its spans to `localhost:8080/otlp-http/` |
| Jaeger | http://localhost:8080/jaeger/ui/ | |
| Grafana | http://localhost:8080/grafana/ | anonymous access as Admin, no login |
| Load Generator | http://localhost:8080/loadgen/ | k6 |
| Feature Flags | http://localhost:8080/feature | flagd-ui |
| Argo CD | https://localhost:8443/ | `admin` / password from `bootstrap-argocd.sh`; self-signed certificate |

CLI login: `argocd login localhost:8443 --username admin --password '<password>' --insecure`.

## Distributed trace verification

1. Open http://localhost:8080/, open a product, **Add to Cart**, **Cart**, **Place Order**.
   The checkout path crosses many services.
2. Open http://localhost:8080/jaeger/ui/, Service `frontend`, Operation `POST /api/checkout`, **Find Traces**,
   open the trace with the most spans.
3. To tell your request apart from the k6 load generator (5 VUs, always on): filter by time, or look for a trace
   whose root span comes from `frontend-web` (browser SDK). Whether k6's browser mode also produces `frontend-web`
   spans has to be checked on real data.
4. Record Trace ID, services, span flow, `service.name` values and representative attributes in
   [baseline/trace-2026-09-04.md](baseline/trace-2026-09-04.md).

Where the identifying attributes come from:

- `service.name`: each pod's `OTEL_SERVICE_NAME`, taken from the label `app.kubernetes.io/component`.
- `service.instance.id`: inserted by the Collector `resource` processor from `k8s.pod.uid`.
- `service.namespace=opentelemetry-demo`: pod annotation `resource.opentelemetry.io/service.namespace`, picked up by the k8sattributes preset.

These three exist because the data went through the Collector, which matters for the CloudWatch Agent comparison.

## GitOps demo (Git -> Argo CD -> Kubernetes)

1. Edit `otel-demo/values/local.yaml`:

   ```yaml
   components:
     frontend:
       replicas: 2
   ```

2. `git commit -am "Scale frontend to 2 replicas for GitOps check" && git push`
3. Argo CD polls Git every 3 minutes by default (`timeout.reconciliation`). To see it immediately:

   ```bash
   argocd app get otel-demo --refresh     # Sync Status: OutOfSync
   argocd app diff otel-demo              # Deployment frontend: replicas 1 -> 2
   ```

4. `argocd app sync otel-demo`, then `kubectl -n otel-demo get deployment frontend` shows `2/2`.
5. Revert the change in Git (remove the block), push, refresh, Sync: back to `1/1`. The baseline stays at upstream defaults.

## Drift demo (cluster changed behind Git's back)

```bash
kubectl -n otel-demo scale deployment/frontend --replicas=2   # 1. change the cluster only
argocd app get otel-demo --refresh                              # 2. OutOfSync (the resource watch usually catches it within seconds)
argocd app diff otel-demo                                       # 3. live (2) vs desired in Git (1)
argocd app sync otel-demo                                       # 4. back to the Git state
kubectl -n otel-demo get deployment frontend                    #    1/1
```

Self-heal is not enabled, so the drift stays until you Sync.

## Baseline for the AWS comparison

- Chart: `opentelemetry-demo` 0.41.0 / appVersion 3.0.0.
- Components disabled in `otel-demo/values/local.yaml` (a deviation from upstream defaults): agent, mcp, chatbot, telemetry-docs,
  load-generator. Reason and numbers: Verification status above. Both comparison conditions must use the same set; if load is
  wanted, re-enable load-generator with the same VU count in both.
- Collector: `otel/opentelemetry-collector-contrib`, `mode: daemonset`, Service `otel-collector` (4317 / 4318),
  presets hostMetrics, kubernetesAttributes, kubeletMetrics, clusterMetrics, annotationDiscovery (metrics);
  extensions `health_check`, `opamp` (-> `opamp-server:4320`).

  | pipeline | receivers | processors | exporters |
  |---|---|---|---|
  | traces | sub-chart default (not set in demo values) | memory_limiter, resourcedetection, resource, transform/sanitize_logs, gen_ai_normalizer | otlp_grpc/jaeger, debug, span_metrics |
  | metrics | otlp, kafkametrics, span_metrics, prometheus/ad | memory_limiter, resourcedetection, resource | otlp_http/prometheus, debug |
  | logs | sub-chart default | memory_limiter, resourcedetection, resource, transform/sanitize_logs | opensearch, debug |
  | profiles | otlp | memory_limiter, resourcedetection, resource, filter/sanitize_profiles | otlp_grpc/firepit, debug |

  Receivers not listed in the demo values, and processors injected by presets, come from the `opentelemetry-collector`
  sub-chart. Effective config as rendered locally with `helm template` on 2026-09-04 (confirm on the cluster with
  `argocd app manifests otel-demo` or `kubectl -n otel-demo get configmap otel-collector -o yaml`):

  - traces: receivers `otlp, jaeger, zipkin`; processors `k8s_attributes, memory_limiter, resourcedetection, resource, transform/sanitize_logs, gen_ai_normalizer`; exporters as above.
  - metrics: receivers additionally `receiver_creator/metrics, hostmetrics, kubeletstats, k8s_cluster`; `k8s_attributes` first in processors.
  - logs / profiles: receivers `otlp`; `k8s_attributes` first in processors.
  - extensions: `health_check, opamp, k8s_observer, k8s_leader_elector/k8s_cluster`.
- Array override caution: the docs say to keep the `spanmetrics` exporter when overriding; in chart 0.41.0 the connector is
  named `span_metrics`. Overriding `service.pipelines.traces.exporters` replaces the array, so restate
  `[otlp_grpc/jaeger, debug, span_metrics, ...]`.
- Recorded trace: [baseline/trace-2026-09-04.md](baseline/trace-2026-09-04.md) (fill in after the first run).
- Main `service.name` values expected on the checkout path: frontend-web, frontend-proxy, frontend, checkout, cart, currency,
  payment, shipping, quote, email, product-catalog, kafka, accounting, fraud-detection.
- Where to change things for CloudWatch, and how to keep the two conditions comparable: [experiments/README.md](experiments/README.md).

## If the Mac runs out of memory

- Detect: `kubectl -n otel-demo get pods` (OOMKilled, growing RESTARTS), `docker stats otel-demo-control-plane`.
  kind has no metrics-server, so `kubectl top` does not work.
- Observed 2026-09-04: the first Sync of the full chart drove the kind node to a load average above 100 and the Mac into 5 GB of
  swap. kube-apiserver, etcd, CoreDNS and `argocd-repo-server` restarted repeatedly on failed liveness probes, so neither `argocd`
  nor `kubectl` reached the cluster reliably for about 30 minutes and three sync attempts failed inside Argo CD (DNS timeout,
  repo-server in CrashLoopBackOff). What worked: `kubectl -n otel-demo scale deployment agent mcp chatbot telemetry-docs
  load-generator --replicas=0` (one API call each, no dependency on in-cluster DNS or the repo-server; CPU fell from 540% to
  60% within a minute), then a sync with prune once `argocd-repo-server` was Ready. A sync can be requested without the CLI:
  `kubectl -n argocd patch application otel-demo --type merge -p '{"operation":{"sync":{"prune":true,"revisions":["0.41.0","main"]}}}'`.
- Disable in this order, least impact on the tracing check first, via `components.<name>.enabled: false` in `local.yaml`:
  `agent`, `mcp`, `chatbot` (1500Mi total, LLM demo, not on the checkout path) -> `telemetry-docs` (100Mi) ->
  `load-generator` (512Mi; traces then only come from your own clicks).
- Side effects: `opamp-server` is referenced by the Collector `opamp` extension and `opensearch` by the logs pipeline;
  disabling either needs an array override of the Collector config. Disabling `kafka` may break order publishing in checkout.
- Minimum set for the distributed-trace check: frontend-proxy, frontend, product-catalog (+ astronomy-db), cart (+ valkey-cart),
  currency, checkout, payment, shipping, quote, email, ad, recommendation, image-provider, flagd, kafka (+ accounting, fraud-detection),
  otel-collector, jaeger.

## Cleanup

```bash
./scripts/cleanup.sh              # kind delete cluster --name otel-demo
docker image prune -a             # optional: also drop the pulled images
kubectl config get-contexts       # kind-otel-demo should be gone
```

To restore the previous Rancher Desktop VM size: `rdctl set --virtual-machine.memory-in-gb 8 --virtual-machine.number-cpus 4`.
