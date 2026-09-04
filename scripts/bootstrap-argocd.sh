#!/usr/bin/env bash
# Install Argo CD into the kind cluster.
# This is the only place where kubectl is used for deployment: Argo CD bootstraps itself,
# everything else (Astronomy Shop) is deployed through Argo CD.
# The official install.yaml is applied with a pinned version.
set -euo pipefail

ARGOCD_VERSION="v3.5.2"
INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# Server-side apply is required. Client-side apply stores each object again in the
# kubectl.kubernetes.io/last-applied-configuration annotation, whose limit is 262144 bytes.
# In v3.5.2 the applicationsets.argoproj.io CRD is 1,394,816 bytes as YAML and fails with
# "metadata.annotations: Too long: must have at most 262144 bytes"; the applications CRD
# (405,969 bytes as YAML, 197,612 as compact JSON) still fits. Observed on 2026-09-04: with
# client-side apply only 2 of 3 CRDs were created and argocd-applicationset-controller
# crash-looped with 'no matches for kind "ApplicationSet"'.
kubectl apply -n argocd --server-side -f "${INSTALL_URL}"

kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

echo
echo "Argo CD ${ARGOCD_VERSION} is ready."
echo "Initial admin password (user: admin):"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
echo
