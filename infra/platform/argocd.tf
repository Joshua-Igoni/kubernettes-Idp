resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.52.1"

  create_namespace = true

  values = [yamlencode({
    server = {
      service = { type = "ClusterIP" }
    }
  })]
}
