# Experiments (planned, not implemented yet)

This directory holds the plan for comparing two telemetry paths on top of the baseline in this repository.
No AWS resources exist yet. Nothing below is implemented as of 2026-09-04.

## Decisions (2026-09-04)

- **The comparison runs on the same kind cluster, not on EKS**, to avoid cost. Consequences:
  - No IRSA. AWS credentials for the Collector exporter (A) and the CloudWatch Agent (B) are passed as static
    credentials through env or a Kubernetes Secret, decided on the day. Secrets are never committed to this repo.
  - Node-oriented CloudWatch Agent features that assume EKS (Container Insights) are out of scope.
- **Both conditions use the reduced component set** from `otel-demo/values/local.yaml`: agent, mcp, chatbot,
  telemetry-docs and load-generator disabled. The full chart saturated the 10 GB VM on this Mac
  (README, Verification status). After the reduction the node uses about 6.9 GiB of 9.7 GiB, which leaves room for
  one CloudWatch Agent Deployment; if more is needed, disable opensearch next (requires overriding the logs pipeline
  exporters, e.g. `[debug]`).
- Traffic: either keep load-generator disabled in both conditions and drive the same manual checkout, or re-enable
  it in both with the same VU count. Never enable it on one side only.

## Current path (baseline)

```text
[service pods] --OTLP gRPC 4317 / HTTP 4318--> Service otel-collector (DaemonSet, otel/opentelemetry-collector-contrib)
[browser: frontend-web] --/otlp-http/--> frontend-proxy (Envoy) --> otel-collector:4318
otel-collector --traces  (otlp_grpc)      --> jaeger:4317                       -> Jaeger UI  (/jaeger/ui/)
otel-collector --metrics (otlp_http)      --> prometheus:9090/api/v1/otlp       -> Grafana    (/grafana/)
otel-collector --logs    (opensearch)     --> opensearch:9200 (index otel-logs) -> Grafana
```

Every service builds its endpoint from the shared env `OTEL_COLLECTOR_NAME=otel-collector`
(e.g. `http://$(OTEL_COLLECTOR_NAME):4317`), so the destination can be switched in one place.

## Experiment A: upstream OTel Collector -> CloudWatch

- Values file: `otel-demo/values/upstream-cloudwatch.yaml` (copy of `local.yaml` plus the change below).
- Change only `opentelemetry-collector.config`:
  - add an AWS exporter under `exporters` (exact exporter to be chosen on the day),
  - rewrite `service.pipelines.traces.exporters` with all elements:
    `[otlp_grpc/jaeger, debug, span_metrics, <aws exporter>]` (array override replaces the list).
- Do not touch application env; the apps keep sending to `otel-collector`.
- Credentials: kind has no IRSA. How to pass credentials is decided on the day (out of scope for the baseline).
- Switch by editing `valueFiles` in `argocd/application.yaml`, then Sync.

## Experiment B: CloudWatch Agent -> CloudWatch

- Deploy the CloudWatch Agent as a separate Deployment + Service that accepts OTLP on 4317/4318.
  It is outside the demo chart, so it becomes a second Argo CD Application (e.g. `argocd/cloudwatch-agent.yaml`).
- Values file: `otel-demo/values/cloudwatch-agent.yaml`. The only application-side change is
  `default.envOverrides` setting `OTEL_COLLECTOR_NAME` to the agent's Service name.
  All components, including the browser path through frontend-proxy `/otlp-http/`, follow that env.

## Keeping the comparison fair

- Same chart version (0.41.0), same set of enabled components (the reduced set above), same traffic source in both
  (load-generator off in both, or on in both with the same VU count).
- Same sampling: SDK defaults, no sampling in the Collector. Do not add tail sampling to one side only.
- Attributes that exist only because of the Collector path, record them as a difference rather than a bug:
  `service.instance.id` (resource processor), `k8s.*` (k8sattributes preset), `host.*` (resourcedetection).
- `transform/sanitize_spans` and the `span_metrics` connector exist only in the Collector path
  (span-name normalization and RED metrics).
- Protocols differ per service: checkout and shipping use http/protobuf, most others use gRPC.
  The agent must accept both.
- W3C trace-id vs X-Ray id conversion and how span attributes are displayed in CloudWatch:
  check on real data on the day, do not write from assumptions.
