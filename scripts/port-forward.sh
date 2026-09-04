#!/usr/bin/env bash
# Start the port-forwards needed to reach the local UIs. Ctrl+C stops both.
#   http://localhost:8080/            Astronomy Shop (via frontend-proxy / Envoy)
#   http://localhost:8080/jaeger/ui/  Jaeger
#   http://localhost:8080/grafana/    Grafana
#   http://localhost:8080/loadgen/    Load Generator (k6)
#   http://localhost:8080/feature     Feature Flags UI (flagd-ui)
#   https://localhost:8443/           Argo CD (admin / password printed by bootstrap-argocd.sh)
# Port 8080 is not arbitrary: the frontend tells the browser to send its spans to
# http://localhost:8080/otlp-http/v1/traces (PUBLIC_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT).
set -euo pipefail

kubectl -n otel-demo port-forward svc/frontend-proxy 8080:8080 &
kubectl -n argocd    port-forward svc/argocd-server  8443:443  &

trap 'kill 0' EXIT INT TERM
wait
