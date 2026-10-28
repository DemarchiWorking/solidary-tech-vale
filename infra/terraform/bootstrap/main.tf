# ============================================
# Bootstrap do projeto GCP (uma vez, com credencial de usuário)
# ============================================
# Antes (gcloud, porque o Terraform precisa delas para habilitar o resto):
#   gcloud services enable cloudresourcemanager.googleapis.com serviceusage.googleapis.com
#
# Cria: APIs, bucket do state, federação de identidade do GitHub (sem chave)
# e as service accounts do CI, cada uma presa a um tipo de job:
#   ci-deployer        imagens no Artifact Registry       -> push na branch padrão
#   ci-selfheal        kubectl rollout restart (RBAC)      -> push/dispatch na branch padrão
#   ci-terraform-plan  plan em pull request (leitura)      -> pull_request
#   ci-terraform       apply                               -> environment "production"

data "google_project" "this" {
  project_id = var.project_id
}

locals {
  apis = [
    "artifactregistry.googleapis.com",
    "billingbudgets.googleapis.com",
    "certificatemanager.googleapis.com",
    "cloudscheduler.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "firestore.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "monitoring.googleapis.com",
    "pubsub.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
  ]

  repository = "${var.github_owner}/${var.github_repo}"

  # Condição da federação: com os IDs numéricos (imutáveis), um repositório
  # recriado com o mesmo nome não herda o acesso. Sem eles, cai no nome.
  attribute_condition = (
    var.github_repository_id != "" && var.github_owner_id != ""
    ? "assertion.repository_id == '${var.github_repository_id}' && assertion.repository_owner_id == '${var.github_owner_id}'"
    : "assertion.repository == '${local.repository}'"
  )

  pool        = google_iam_workload_identity_pool.github.name
  subject     = "principal://iam.googleapis.com/${local.pool}/subject"
  default_ref = "principalSet://iam.googleapis.com/${local.pool}/attribute.ref/refs/heads/${var.default_branch}"
  terraform_roles = [
    "roles/artifactregistry.admin",
    "roles/certificatemanager.owner",
    "roles/cloudscheduler.admin",
    "roles/cloudsql.admin",
    "roles/compute.networkAdmin",
    "roles/compute.securityAdmin",
    "roles/container.admin",
    "roles/datastore.owner",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/monitoring.editor",
    "roles/pubsub.admin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/servicenetworking.networksAdmin",
    "roles/storage.admin",
  ]
}

resource "google_project_service" "apis" {
  for_each = toset(local.apis)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# O agente do Pub/Sub (quem move mensagens para a DLQ) só nasce no primeiro
# uso; pedir a identidade explicitamente garante que ele exista antes dos
# bindings da stack de infraestrutura.
resource "google_project_service_identity" "pubsub" {
  provider = google-beta

  project = var.project_id
  service = "pubsub.googleapis.com"

  depends_on = [google_project_service.apis]
}

# --- State do Terraform ---
resource "google_storage_bucket" "tfstate" {
  project                     = var.project_id
  name                        = "${var.project_id}-tfstate"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 20
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.apis]
}

# --- Federação de identidade do GitHub Actions ---
resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"

  depends_on = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions"
  display_name                       = "GitHub Actions OIDC"

  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.repository"          = "assertion.repository"
    "attribute.repository_id"       = "assertion.repository_id"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.ref"                 = "assertion.ref"
    "attribute.environment"         = "assertion.environment"
  }

  attribute_condition = local.attribute_condition

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# --- Service accounts do CI ---
resource "google_service_account" "ci" {
  for_each = {
    ci-deployer       = "CI: publica imagens no Artifact Registry"
    ci-selfheal       = "CI: self-heal (rollout restart via RBAC)"
    ci-terraform-plan = "CI: terraform plan em pull request (leitura)"
    ci-terraform      = "CI: terraform apply (environment production)"
  }

  project      = var.project_id
  account_id   = each.key
  display_name = each.value
}

# Quem pode se passar por cada SA.
resource "google_service_account_iam_member" "deployer_wif" {
  service_account_id = google_service_account.ci["ci-deployer"].name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.default_ref
}

resource "google_service_account_iam_member" "selfheal_wif" {
  service_account_id = google_service_account.ci["ci-selfheal"].name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.default_ref
}

resource "google_service_account_iam_member" "plan_wif" {
  service_account_id = google_service_account.ci["ci-terraform-plan"].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "${local.subject}/repo:${local.repository}:pull_request"
}

resource "google_service_account_iam_member" "terraform_wif" {
  service_account_id = google_service_account.ci["ci-terraform"].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "${local.subject}/repo:${local.repository}:environment:production"
}

# O que cada SA pode fazer. O ci-deployer recebe escrita só no repositório
# do Artifact Registry (envs/prod/infra, variável ci_deployer_service_account).
#
# Self-heal: o endpoint DNS do GKE exige container.clusters.connect, que a
# documentação dá por roles/container.viewer ou container.developer
# (clusterViewer não basta). viewer é só leitura e não lê Secrets; reiniciar
# Deployments vem do RBAC (modules/platform, Role selfheal-rollout-restart).
resource "google_project_iam_member" "selfheal" {
  project = var.project_id
  role    = "roles/container.viewer"
  member  = "serviceAccount:${google_service_account.ci["ci-selfheal"].email}"
}

resource "google_project_iam_member" "plan" {
  for_each = toset(["roles/viewer", "roles/iam.securityReviewer"])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.ci["ci-terraform-plan"].email}"
}

resource "google_storage_bucket_iam_member" "plan_state" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.ci["ci-terraform-plan"].email}"
}

resource "google_project_iam_member" "terraform" {
  for_each = toset(local.terraform_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.ci["ci-terraform"].email}"
}

resource "google_storage_bucket_iam_member" "terraform_state" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.ci["ci-terraform"].email}"
}

# --- Orçamento (opcional: precisa do ID da conta de faturamento) ---
resource "google_billing_budget" "monthly" {
  count = var.billing_account == "" ? 0 : 1

  billing_account = var.billing_account
  display_name    = "SolidaryTech - orçamento mensal"

  budget_filter {
    projects = ["projects/${data.google_project.this.number}"]
  }

  amount {
    specified_amount {
      currency_code = var.budget_currency
      units         = tostring(var.budget_amount)
    }
  }

  dynamic "threshold_rules" {
    for_each = [0.5, 0.9, 1.0]
    content {
      threshold_percent = threshold_rules.value
    }
  }

  depends_on = [google_project_service.apis]
}
