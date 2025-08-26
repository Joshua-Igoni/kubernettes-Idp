CLUSTER ?= kubernettes-idp
NS_ARGO ?= argocd
DOMAIN ?= kubernettes.local

.PHONY: kind-up kind-down argo-bootstrap app-bootstrap hosts
kind-up:
	kind create cluster --name $(CLUSTER) --config hack/kind-config.yaml
	kubectl wait --for=condition=Ready pods --all -A --timeout=180s || true

kind-down:
	kind delete cluster --name $(CLUSTER)

argo-bootstrap:
	kubectl create ns $(NS_ARGO) --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n $(NS_ARGO) -f bootstrap/argocd-install.yaml
	kubectl -n $(NS_ARGO) rollout status deploy/argocd-server --timeout=180s
	kubectl apply -n $(NS_ARGO) -f bootstrap/app-of-apps.yaml

app-bootstrap:
	kubectl apply -f clusters/dev/applications.yaml

hosts:
	@echo "127.0.0.1 $(DOMAIN)" | sudo tee -a /etc/hosts
