# ============================================
# DR — plataforma no cluster de contingência (só no failover)
# ============================================
# Pré-requisitos (runbook 05): réplica promovida e
# envs/dr/infra aplicado com cluster_enabled = true.
# Os serviços passam a usar a réplica promovida: as URLs de banco são as de
# produção com o host trocado pelo IP privado da réplica.

data "terraform_remote_state" "prod" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "prod/infra"
  }
}

data "terraform_remote_state" "dr" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "dr/infra"
  }
}

locals {
  prod = data.terraform_remote_state.prod.outputs
  dr   = data.terraform_remote_state.dr.outputs

  database_urls = {
    for svc, url in local.prod.database_urls :
    svc => replace(url, "@${local.prod.sql_private_ip}:", "@${local.dr.sql_replica_private_ip}:")
  }
}

module "platform" {
  source = "../../../modules/platform"

  project_id               = local.prod.project_id
  database_urls            = local.database_urls
  sonarqube_db_password    = local.prod.sonarqube_db_password
  datadog_api_key          = var.datadog_api_key
  gitops_repo_url          = "https://github.com/${var.github_repository}.git"
  argocd_github_token      = var.argocd_github_token
  selfheal_service_account = var.selfheal_service_account
}
