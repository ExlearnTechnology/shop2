#!/usr/bin/env bash
set -euo pipefail

# Test-only: both internet-facing endpoints use HTTP and allow all IPv4 addresses.
# Prometheus has no authentication; Grafana uses the requested weak test password.
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic monitoring-grafana-admin \
  --namespace monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password=123456 \
  --dry-run=client -o yaml | kubectl apply -f -

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo update prometheus-community

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.admin.existingSecret=monitoring-grafana-admin \
  --set grafana.ingress.enabled=false \
  --set prometheus.prometheusSpec.retention=7d

# Grafana ALB; no host is configured, so use the raw ALB DNS name.
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: monitoring
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
    alb.ingress.kubernetes.io/inbound-cidrs: "0.0.0.0/0"
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: monitoring-grafana
                port:
                  number: 80
EOF

# Prometheus gets a separate ALB. It has no built-in authentication.
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prometheus
  namespace: monitoring
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
    alb.ingress.kubernetes.io/inbound-cidrs: "0.0.0.0/0"
    alb.ingress.kubernetes.io/healthcheck-path: /-/healthy
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: monitoring-kube-prometheus-prometheus
                port:
                  number: 9090
EOF

# These show the raw AWS ALB DNS names after the controller provisions them.
kubectl get ingress grafana prometheus --namespace monitoring

# If a pod is Pending or an ALB has no address, inspect its events:
kubectl get pods --namespace monitoring
kubectl describe pods --namespace monitoring
kubectl describe ingress grafana prometheus --namespace monitoring
