# 🚀 kubernettes-idp

A **Kubernetes Internal Developer Platform (IDP)** demo, powered by [Kind](https://kind.sigs.k8s.io/), [ArgoCD](https://argo-cd.readthedocs.io/), and [Argo Rollouts](https://argoproj.github.io/argo-rollouts/).  
It shows how to bootstrap a self-service platform, deploy a sample Python service, and expose it via NGINX ingress.

---

## ✨ Features

- **Kind-based cluster** (local K8s for testing)
- **ArgoCD App-of-Apps** pattern for bootstrapping platform components
- **Argo Rollouts** for progressive delivery
- **External Secrets** (placeholder, demo setup)
- **Ingress-NGINX** with NodePort for local development
- **Sample Service** (Python + Gunicorn + health endpoint)

---

## 🛠 Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [Kind](https://kind.sigs.k8s.io/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [make](https://www.gnu.org/software/make/)

Optional (for debugging):
- [ArgoCD CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/)

---

## 🚦 Quickstart

Spin up the full demo locally:

```bash
make demo
