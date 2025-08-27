# ------- Makefile (kubernettes-idp) -------
SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eo pipefail -c
.DEFAULT_GOAL := help

CLUSTER            ?= kubernettes-idp
ARGO_VERSION       ?= v2.10.6
INGRESS_CHART_VER  ?= 4.10.0
TIMEOUT            ?= 600s

APP_NAME           ?= sample-service
APP_RELEASE        ?= sample-service-dev
APP_NS             ?= demo
APP_CHART_PATH     ?= apps/sample-service
APP_VALUES_KIND    ?= values/values-kind.yaml
LOCAL_IMAGE        ?= local/kubernettes-sample
LOCAL_TAG          ?= dev

.PHONY: help
help:
	@echo "Targets:"
	@echo "  kind-up           Create kind cluster"
	@echo "  kind-down         Delete kind cluster"
	@echo "  argo              Install ArgoCD $(ARGO_VERSION)"
	@echo "  bootstrap         Apply app-of-apps + platform apps + sample app"
	@echo "  nginx             Ensure ingress-nginx ready (NodePort on kind)"
	@echo "  app               Build + load local image and force app refresh"
	@echo "  status            Show key Argo and k8s resources"
	@echo "  pf                Port-forward NGINX 8080->80"
	@echo "  demo              Full local run: kind-up argo bootstrap nginx app status pf"
	@echo "  clean             Delete cluster and exit"

# --------------------- cluster ---------------------

.PHONY: kind-up
kind-up:
	kind create cluster --name $(CLUSTER) --config hack/kind-config.yaml
	kubectl wait --for=condition=Ready nodes --all --timeout=120s || true

.PHONY: kind-down
kind-down:
	kind delete cluster --name $(CLUSTER)

# --------------------- argo -----------------------

.PHONY: argo
argo:
	kubectl create ns argocd --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/$(ARGO_VERSION)/manifests/install.yaml
	kubectl -n argocd rollout status deploy/argocd-server --timeout=$(TIMEOUT)

# ------------------- bootstrap --------------------

.PHONY: bootstrap
bootstrap:
	# App-of-Apps (points to clusters/dev)
	kubectl apply -n argocd -f bootstrap/app-of-apps.yaml || true
	# Platform child apps (ingress-nginx, argo-rollouts, external-secrets)
	kubectl apply -f clusters/dev/application.yaml
	# Sample app Application (must exist; includes CreateNamespace=true)
	-kubectl apply -f clusters/dev/sample-app.yaml
	# Kick Argo to reconcile everything
	kubectl -n argocd annotate application ingress-nginx argocd.argoproj.io/refresh=hard --overwrite || true
	kubectl -n argocd annotate application $(APP_RELEASE) argocd.argoproj.io/refresh=hard --overwrite || true
	# Wait until the Application CRs are visible
	kubectl -n argocd get application

# ---------------- ingress-nginx (kind) ------------

.PHONY: nginx
nginx:
	# Ensure Argo can create namespaces automatically
	kubectl -n argocd patch application ingress-nginx --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true},"syncOptions":["CreateNamespace=true"]}}}' || true
	# Pre-create ns to avoid race if Argo is slow
	kubectl create namespace ingress-nginx 2>/dev/null || true
	# Switch the Service to NodePort for kind (health will go green)
	kubectl -n argocd patch application ingress-nginx --type merge -p '{
	  "spec": { "source": { "helm": { "values": "controller:\n  service:\n    type: NodePort\n    nodePorts:\n      http: 30080\n      https: 30443\n" } } }
	}' || true
	kubectl -n argocd annotate application ingress-nginx argocd.argoproj.io/refresh=hard --overwrite || true
	# Wait for controller to be ready
	kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=$(TIMEOUT) || \
	  (echo "ingress-nginx-controller not found yet; checking resources..." && kubectl -n ingress-nginx get all && exit 1)
	# Show resulting svc
	kubectl -n ingress-nginx get svc ingress-nginx-controller -o wide

# -------------------- sample app ------------------

.PHONY: app
app:
	# Build and load local image into kind
	docker build -t $(LOCAL_IMAGE):$(LOCAL_TAG) $(APP_CHART_PATH)
	kind load docker-image $(LOCAL_IMAGE):$(LOCAL_TAG) --name $(CLUSTER)
	# Force Argo to use our kind values (lives inside the chart)
	kubectl -n argocd patch application $(APP_RELEASE) --type merge -p '{
	  "spec":{"source":{"helm":{"valueFiles":["$(APP_VALUES_KIND)"]}}}
	}' || true
	# Ensure Argo can create the demo namespace and prune last
	kubectl -n argocd patch application $(APP_RELEASE) --type merge -p '{
	  "spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true},"syncOptions":["CreateNamespace=true","PruneLast=true"]}}
	}' || true
	# Refresh app and wait for rollout
	kubectl -n argocd annotate application $(APP_RELEASE) argocd.argoproj.io/refresh=hard --overwrite || true
	# Wait for namespace to exist
	until kubectl get ns $(APP_NS) >/dev/null 2>&1; do echo "waiting for $(APP_NS) ns..."; sleep 3; done
	kubectl -n $(APP_NS) get rollout,svc,ingress || true

# -------------------- convenience -----------------

.PHONY: status
status:
	kubectl -n argocd get application
	kubectl get ns | grep -E 'ingress-nginx|$(APP_NS)' || true
	kubectl -n ingress-nginx get deploy,svc,pods || true
	kubectl -n $(APP_NS) get rollout,svc,ingress,pods -o wide || true

.PHONY: pf
pf:
	# Requires nginx target to have completed
	kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:80

.PHONY: demo
demo: kind-up argo bootstrap nginx app status pf

.PHONY: clean
clean: kind-down
# ------- /Makefile -------
