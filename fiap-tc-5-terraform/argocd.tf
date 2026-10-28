# ============================================
# ArgoCD (via Helm)
# ============================================

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "9.4.15"
  namespace        = "argocd"
  create_namespace = true

  # Repositório fiap-tc-5-gitops privado: o ArgoCD autentica com
  # argocd_github_token (fine-grained, só leitura de Contents nesse
  # repositório). Com a variável vazia, clona sem credencial, o que só
  # funciona se o repositório for público.
  set = [
    {
      name  = "server.service.type"
      value = "LoadBalancer"
    },
    {
      name  = "configs.repositories.gitops-repo.url"
      value = "https://github.com/${local.gitops_repo}.git"
    },
    {
      name  = "configs.repositories.gitops-repo.type"
      value = "git"
    },
    {
      name  = "configs.params.kustomize\\.buildOptions"
      value = "--enable-helm"
    },
  ]

  set_sensitive = var.argocd_github_token == "" ? [] : [
    {
      name  = "configs.repositories.gitops-repo.username"
      value = "x-access-token"
    },
    {
      name  = "configs.repositories.gitops-repo.password"
      value = var.argocd_github_token
    },
  ]

  depends_on = [azurerm_kubernetes_cluster.aks]
}

# ============================================
# Ingress NGINX (via Helm)
# ============================================

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.12.1"
  namespace        = "ingress-nginx"
  create_namespace = true

  set = [
    {
      name  = "controller.service.type"
      value = "LoadBalancer"
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-health-probe-request-path"
      value = "/healthz"
    },
    {
      name  = "controller.admissionWebhooks.enabled"
      value = "false"
    },
  ]

  depends_on = [azurerm_kubernetes_cluster.aks]
}
