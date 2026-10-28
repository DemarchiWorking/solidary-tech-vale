# ============================================
# Produção (southamerica-east1) — infraestrutura GCP
# ============================================
# Só provider google aqui. O que roda dentro do cluster (ArgoCD, Secrets)
# fica em envs/prod/platform, que lê os outputs desta stack.

data "google_project" "this" {
  project_id = var.project_id
}

locals {
  labels = {
    project     = "solidarytech"
    environment = "production"
    costcenter  = "ngo-core"
    managed-by  = "terraform"
  }

  name = "solidarytech"
}

module "network" {
  source = "../../../modules/network"

  project_id = var.project_id
  name       = "${local.name}-vpc"
  psa_cidr   = "10.40.0.0/16"

  subnets = {
    prod = {
      region        = var.region
      nodes_cidr    = "10.10.0.0/20"
      pods_cidr     = "10.16.0.0/14"
      services_cidr = "10.20.0.0/20"
    }
    # Pronta para o DR (réplica do Cloud SQL e cluster de contingência na
    # mesma VPC). Sub-rede e NAT sem tráfego não geram custo relevante.
    dr = {
      region        = var.dr_region
      nodes_cidr    = "10.30.0.0/20"
      pods_cidr     = "10.32.0.0/14"
      services_cidr = "10.36.0.0/20"
    }
  }
}

module "gke" {
  source = "../../../modules/gke"

  project_id          = var.project_id
  name                = "${local.name}-prod"
  region              = var.region
  node_locations      = var.node_locations
  network             = module.network.network_id
  subnetwork          = module.network.subnet_names["prod"]
  pods_range_name     = module.network.pods_range_name
  services_range_name = module.network.services_range_name
  master_authorized_cidrs = {
    nos-prod = "10.10.0.0/20"
  }
  machine_type        = var.node_machine_type
  min_nodes_per_zone  = var.min_nodes_per_zone
  max_nodes_per_zone  = var.max_nodes_per_zone
  deletion_protection = var.deletion_protection
  labels              = merge(local.labels, { component = "kubernetes" })
}

# --- Artifact Registry: imagens dos 4 serviços ---
resource "google_artifact_registry_repository" "images" {
  project       = var.project_id
  location      = var.region
  repository_id = "solidarytech"
  format        = "DOCKER"
  description   = "Imagens dos serviços da SolidaryTech (tag = SHA do commit)"
  labels        = merge(local.labels, { component = "registry" })

  # Tag imutável: o que o GitOps aponta nunca muda por baixo.
  docker_config {
    immutable_tags = true
  }

  # FinOps: guarda as 20 versões mais recentes de cada imagem e apaga o
  # resto depois de 30 dias.
  cleanup_policy_dry_run = false
  cleanup_policies {
    id     = "manter-20-recentes"
    action = "KEEP"
    most_recent_versions {
      keep_count = 20
    }
  }
  cleanup_policies {
    id     = "apagar-antigas"
    action = "DELETE"
    condition {
      older_than = "2592000s"
    }
  }
}

resource "google_artifact_registry_repository_iam_member" "nodes_reader" {
  project    = var.project_id
  location   = google_artifact_registry_repository.images.location
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${module.gke.node_service_account}"
}

resource "google_artifact_registry_repository_iam_member" "ci_writer" {
  count = var.ci_deployer_service_account == "" ? 0 : 1

  project    = var.project_id
  location   = google_artifact_registry_repository.images.location
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${var.ci_deployer_service_account}"
}

module "data" {
  source = "../../../modules/data"

  project_id            = var.project_id
  project_number        = data.google_project.this.number
  name                  = local.name
  region                = var.region
  backup_region         = var.dr_region
  network_id            = module.network.network_id
  firestore_location    = var.region
  sql_tier              = var.sql_tier
  sql_availability_type = "REGIONAL"
  deletion_protection   = var.deletion_protection
  labels                = local.labels

  # O IP privado do Cloud SQL depende da conexão do Private Service Access.
  depends_on = [module.network]
}

module "edge" {
  source = "../../../modules/edge"

  project_id = var.project_id
  name       = local.name
  hostname   = var.hostname
  labels     = local.labels
}

module "workload_identity" {
  source = "../../../modules/workload-identity"

  project_id            = var.project_id
  project_number        = data.google_project.this.number
  name                  = local.name
  workload_pool         = module.gke.workload_pool
  events_topic          = module.data.events_topic
  consumer_subscription = module.data.consumer_subscription
  dr_bucket             = module.data.dr_bucket
}

locals {
  sql_passwords = module.data.sql_user_passwords
  sql_host      = module.data.sql_private_ip

  database_urls = {
    ngo      = "postgres://ngo_app:${urlencode(local.sql_passwords["ngo_app"])}@${local.sql_host}:5432/ngo_db?sslmode=require"
    donation = "postgres://donation_app:${urlencode(local.sql_passwords["donation_app"])}@${local.sql_host}:5432/donation_db?sslmode=require"
  }
}
