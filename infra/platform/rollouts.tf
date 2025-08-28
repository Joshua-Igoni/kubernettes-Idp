resource "helm_release" "argo_rollouts" {
  name       = "argo-rollouts"
  namespace  = "argo-rollouts"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-rollouts"
  version    = "2.37.3"
  create_namespace = true

  depends_on = [helm_release.argocd]
}
