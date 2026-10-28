# ============================================
# Produção — o que roda dentro do cluster
# ============================================
# Lê os outputs da stack de infraestrutura (envs/prod/infra) e cria
# namespaces, Secrets, ConfigMap, ArgoCD e o app-of-apps. A partir daí o
# ArgoCD aplica tudo que está em deploy/gitops.

data "terraform_remote_state" "infra" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "prod/infra"
  }
}

locals {
  infra = data.terraform_remote_state.infra.outputs
}

module "platform" {
  source = "../../../modules/platform"

  project_id               = local.infra.project_id
  database_urls            = local.infra.database_urls
  sonarqube_db_password    = local.infra.sonarqube_db_password
  datadog_api_key          = var.datadog_api_key
  gitops_repo_url          = "https://github.com/${var.github_repository}.git"
  gitops_revision          = var.gitops_revision
  argocd_github_token      = var.argocd_github_token
  selfheal_service_account = var.selfheal_service_account
}
