#!/usr/bin/env bash
# Bootstrap Argo CD, Gatekeeper, kube-prometheus-stack, and Falco on the local Kind cluster.
set -euo pipefail

echo "▶ Adding Helm repos"
helm repo add argo            https://argoproj.github.io/argo-helm                >/dev/null
helm repo add gatekeeper      https://open-policy-agent.github.io/gatekeeper/charts >/dev/null
helm repo add prometheus      https://prometheus-community.github.io/helm-charts  >/dev/null
helm repo add falcosecurity   https://falcosecurity.github.io/charts              >/dev/null
helm repo update >/dev/null

echo "▶ Installing Argo CD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install argocd argo/argo-cd -n argocd \
  --set server.extraArgs='{--insecure}' --wait

echo "▶ Installing OPA Gatekeeper"
kubectl create namespace gatekeeper-system --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install gatekeeper gatekeeper/gatekeeper -n gatekeeper-system --wait

echo "▶ Applying Gatekeeper ConstraintTemplates"
kubectl apply -f policies/gatekeeper/templates/
echo "▶ Waiting for templates to register..."
sleep 15
echo "▶ Applying Constraints"
kubectl apply -f policies/gatekeeper/constraints/

if [ "${SKIP_MONITORING:-0}" = "1" ]; then
  echo "▶ Skipping kube-prometheus-stack and Falco (SKIP_MONITORING=1)"
  echo "✅ Core bootstrap complete (Argo CD + Gatekeeper). Run 'make deploy' or 'make violate' next."
  exit 0
fi

echo "▶ Installing kube-prometheus-stack"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install kube-prometheus-stack prometheus/kube-prometheus-stack \
  -n monitoring -f monitoring/prometheus/values.yaml --wait

if [ "${SKIP_FALCO:-0}" = "1" ]; then
  echo "▶ Skipping Falco (SKIP_FALCO=1)"
  echo "✅ Bootstrap complete without Falco. Run 'make deploy' next."
  exit 0
fi

echo "▶ Installing Falco"
kubectl create namespace falco --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install falco falcosecurity/falco -n falco \
  -f security/falco/values.yaml --wait

echo "✅ Bootstrap complete. Run 'make deploy' next."
