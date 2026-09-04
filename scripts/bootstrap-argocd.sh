#!/usr/bin/env bash
# Install Argo CD into the kind cluster.
# This is the only place where kubectl is used for deployment: Argo CD bootstraps itself,
# everything else (Astronomy Shop) is deployed through Argo CD.
# The official install.yaml is applied with a pinned version.
set -euo pipefail

ARGOCD_VERSION="v3.5.2"
INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# If this fails with "metadata.annotations: Too long: must have at most 262144 bytes"
# (CRD too large for client-side apply), switch to:
#   kubectl apply -n argocd --server-side -f "${INSTALL_URL}"
kubectl apply -n argocd -f "${INSTALL_URL}"

kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

echo
echo "Argo CD ${ARGOCD_VERSION} is ready."
echo "Initial admin password (user: admin):"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
echo
