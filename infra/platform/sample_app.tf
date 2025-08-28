resource "kubernetes_namespace" "demo" {
  metadata { name = "demo" }
}

resource "helm_release" "sample_service" {
  name       = "sample-service-dev"
  namespace  = kubernetes_namespace.demo.metadata[0].name
  chart      = "${path.module}/../..//apps/sample-service" # repo-local chart
  create_namespace = false

  values = [yamlencode({
    image = {
      repository = var.ecr_repo_url
      tag        = var.app_tag
      pullPolicy = "IfNotPresent"
    }
    service = { type = "ClusterIP", port = 80 }
    ingress = {
      enabled   = true
      className = "nginx"
      hosts = [{ host = "", paths = [{ path = "/", pathType = "Prefix" }] }] # no custom host; CloudFront hits NLB
      tls   = []
    }
  })]

  depends_on = [helm_release.ingress_nginx]
}
