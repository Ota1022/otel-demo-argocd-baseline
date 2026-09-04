#!/usr/bin/env bash
# Delete the kind cluster. Everything inside it (Argo CD, Astronomy Shop) is removed.
# Pulled Docker images are kept to speed up the next bootstrap; run `docker image prune -a` to drop them.
set -euo pipefail
kind delete cluster --name otel-demo
