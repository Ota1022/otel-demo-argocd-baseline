#!/usr/bin/env bash
# Create the kind cluster "otel-demo" from kind/cluster.yaml (node image pinned by digest).
# Does nothing if a cluster with the same name already exists.
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER_NAME="otel-demo"   # must match `name:` in kind/cluster.yaml

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "kind cluster '${CLUSTER_NAME}' already exists. skip."
else
  kind create cluster --config kind/cluster.yaml
fi

kubectl config use-context "kind-${CLUSTER_NAME}"
kubectl get nodes -o wide
