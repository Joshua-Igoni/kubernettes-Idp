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
	kubectl apply -n argocd -f bootstrap/app-of-apps.yaml || true
	kubectl apply -f clusters/dev/application.yaml
	-kubectl apply -f clusters/dev/sample-app.yaml
	kubectl -n argocd annotate application ingress-nginx argocd.argoproj.io/refresh=hard --overwrite || true
	kubectl -n argocd annotate application $(APP_RELEASE) argocd.argoproj.io/refresh=hard --overwrite || true
	kubectl -n argocd get application

# ---------------- ingress-nginx (kind) ------------

.PHONY: nginx
nginx:
	kubectl apply -f clusters/dev/application.yaml
	kubectl -n argocd patch application ingress-nginx --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true},"syncOptions":["CreateNamespace=true"]}}}' || true
	kubectl create namespace ingress-nginx 2>/dev/null || true

	# Use Helm parameters (less fragile than a values block)
	kubectl -n argocd patch application ingress-nginx --type merge -p '{
	  "spec": {
	    "source": {
	      "helm": {
	        "parameters": [
	          { "name": "controller.service.type", "value": "NodePort" },
	          { "name": "controller.service.nodePorts.http",  "value": "30080" },
	          { "name": "controller.service.nodePorts.https", "value": "30443" }
	        ]
	      }
	    }
	  }
	}'
	# Trigger sync
	kubectl -n argocd patch application ingress-nginx --type merge -p '{"operation":{"sync":{"prune":true}}}'

	# Wait for ns, then for the Deployment to EXIST (Helm sometimes creates the Job first)
	until kubectl get ns ingress-nginx >/dev/null 2>&1; do echo "waiting for namespace ingress-nginx..."; sleep 3; done
	for i in {1..60}; do \
	  if kubectl -n ingress-nginx get deploy/ingress-nginx-controller >/dev/null 2>&1; then break; fi; \
	  echo "waiting for deploy/ingress-nginx-controller to be created..."; sleep 5; \
	done
	kubectl -n ingress-nginx get deploy/ingress-nginx-controller >/dev/null 2>&1 || \
	  (echo "ERROR: deploy/ingress-nginx-controller not created by Helm yet"; kubectl -n argocd describe application ingress-nginx | sed -n '1,140p'; exit 1)

	# Now wait for rollout
	kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=$(TIMEOUT)

	# Ensure Service exists & is NodePort (create once if Helm still catching up)
	if ! kubectl -n ingress-nginx get svc ingress-nginx-controller >/dev/null 2>&1; then \
		cat <<-'YAML' | kubectl apply -n ingress-nginx -f - ;\
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
	fi
	@echo "ingress-nginx Service:"
	kubectl -n ingress-nginx get svc ingress-nginx-controller -o wide
# -------------------- sample app ------------------

.PHONY: app
app:
	@echo "Using image $(LOCAL_IMAGE):$(LOCAL_TAG) with values $(APP_VALUES_KIND)"
	docker build -t $(LOCAL_IMAGE):$(LOCAL_TAG) $(APP_CHART_PATH)
	kind load docker-image $(LOCAL_IMAGE):$(LOCAL_TAG) --name $(CLUSTER)

	# Drive values via Helm parameters so Argo always uses local image
	kubectl -n argocd patch application $(APP_RELEASE) --type merge -p '{
	  "spec": {
	    "source": {
	      "helm": {
	        "valueFiles": ["$(APP_VALUES_KIND)"],
	        "parameters": [
	          { "name": "image.repository", "value": "$(LOCAL_IMAGE)" },
	          { "name": "image.tag",        "value": "$(LOCAL_TAG)" },
	          { "name": "image.pullPolicy", "value": "IfNotPresent" },
	          { "name": "imagePullSecrets", "value": "[]" }
	        ]
	      }
	    },
	    "syncPolicy": { "automated": { "prune": true, "selfHeal": true }, "syncOptions": ["CreateNamespace=true","PruneLast=true"] }
	  }
	}'
	kubectl -n argocd patch application $(APP_RELEASE) --type merge -p '{"operation":{"sync":{"prune":true}}}'

	# Wait for ns, then for the Rollout to EXIST (avoid racing)
	until kubectl get ns $(APP_NS) >/dev/null 2>&1; do echo "waiting for $(APP_NS) ns..."; sleep 3; done
	for i in {1..40}; do \
	  if kubectl -n $(APP_NS) get rollout/$(APP_NAME)-$(APP_RELEASE) >/dev/null 2>&1; then break; fi; \
	  echo "waiting for rollout/$(APP_NAME)-$(APP_RELEASE) to be created..."; sleep 3; \
	done
	kubectl -n $(APP_NS) get rollout/$(APP_NAME)-$(APP_RELEASE) >/dev/null 2>&1 || \
	  (echo "ERROR: rollout not created yet"; kubectl -n argocd describe application $(APP_RELEASE) | sed -n '1,160p'; exit 1)

	# Show current image & policy then wait for rollout
	kubectl -n $(APP_NS) get pods -l app.kubernetes.io/name=$(APP_NAME) -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.spec.containers[0].image}{"  policy="}{.spec.containers[0].imagePullPolicy}{"\n"}{end}' || true
	kubectl -n $(APP_NS) rollout status rollout/$(APP_NAME)-$(APP_RELEASE) --timeout=$(TIMEOUT) || true
	kubectl -n $(APP_NS) get rollout,svc,pods -o wide

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
