# --- 0) quick cluster sanity
kubectl get ns argocd >/dev/null || { echo "Argocd not installed yet. Run: make argo"; exit 1; }

# --- 1) make sure the ingress-nginx Application exists (idempotent)
kubectl apply -f clusters/dev/application.yaml

# --- 2) Set NodePort via Helm *parameters* (beats values/indent issues)
kubectl -n argocd patch application ingress-nginx --type merge -p '{
  "spec": {
    "project": "default",
    "destination": { "namespace": "ingress-nginx", "server": "https://kubernetes.default.svc" },
    "syncPolicy": {
      "automated": { "prune": true, "selfHeal": true },
      "syncOptions": ["CreateNamespace=true"]
    },
    "source": {
      "repoURL": "https://kubernetes.github.io/ingress-nginx",
      "chart": "ingress-nginx",
      "targetRevision": "4.10.0",
      "helm": {
        "parameters": [
          { "name": "controller.service.type", "value": "NodePort" },
          { "name": "controller.service.nodePorts.http", "value": "30080" },
          { "name": "controller.service.nodePorts.https", "value": "30443" }
        ]
      }
    }
  }
}'

# --- 3) Trigger a sync operation (server-side)
kubectl -n argocd patch application ingress-nginx --type merge -p '{"operation":{"sync":{"prune":true}}}'

# --- 4) Wait for namespace and controller to be ready (no noisy errors)
until kubectl get ns ingress-nginx >/dev/null 2>&1; do
  echo "waiting for namespace ingress-nginx..."
  sleep 3
done

# sometimes helm applies Deploy before Svc; wait for the deployment
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=600s || {
  echo "controller not ready; current resources:"; kubectl -n ingress-nginx get all; exit 1;
}

# --- 5) If Service doesn't exist yet, wait a bit and resync once
if ! kubectl -n ingress-nginx get svc ingress-nginx-controller >/dev/null 2>&1; then
  echo "waiting for Service/ingress-nginx-controller..."
  sleep 5
  kubectl -n argocd patch application ingress-nginx --type merge -p '{"operation":{"sync":{"prune":true}}}'
  for i in {1..20}; do
    kubectl -n ingress-nginx get svc ingress-nginx-controller >/dev/null 2>&1 && break
    echo "retrying..."; sleep 3
  done
fi

# show type/ports safely (only if it exists)
if kubectl -n ingress-nginx get svc ingress-nginx-controller >/dev/null 2>&1; then
  kubectl -n ingress-nginx get svc ingress-nginx-controller -o yaml | grep -E "type:|nodePort:|port:"
else
  echo "Service still not found — creating it directly (NodePort) to unblock..."
  cat <<'YAML' | kubectl apply -n ingress-nginx -f -
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/instance: ingress-nginx
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/instance: ingress-nginx
    app.kubernetes.io/component: controller
  ports:
    - name: http
      port: 80
      targetPort: http
      nodePort: 30080
    - name: https
      port: 443
      targetPort: https
      nodePort: 30443
YAML
  kubectl -n ingress-nginx get svc ingress-nginx-controller -o yaml | grep -E "type:|nodePort:|port:"
fi

# --- 6) App image for fresh kind cluster (prevents ErrImagePull)
docker build -t local/kubernettes-sample:dev apps/sample-service
kind load docker-image local/kubernettes-sample:dev --name kubernettes-idp

# Make sure app uses kind values + sane pull policy
kubectl -n argocd patch application sample-service-dev --type merge -p '{
  "spec": {
    "source": { "helm": { "valueFiles": ["values/values-kind.yaml"] } },
    "syncPolicy": { "automated": { "prune": true, "selfHeal": true }, "syncOptions": ["CreateNamespace=true","PruneLast=true"] }
  }
}'
kubectl -n argocd patch application sample-service-dev --type merge -p '{"operation":{"sync":{"prune":true}}}'

# Show final status
kubectl -n argocd get application
kubectl -n demo get rollout,svc,pods -o wide || true
