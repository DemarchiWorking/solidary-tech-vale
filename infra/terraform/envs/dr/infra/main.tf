# ============================================
# DR "pilot light" em southamerica-west1
# ============================================
# Sempre ligado (custo baixo): réplica do Cloud SQL, que dá RPO de segundos
# para as doações. Rede (sub-rede dr) e bucket de backups já existem na
# stack de produção.
#
# Ligado só no failover (cluster_enabled = true, um comando):
#   terraform apply -var cluster_enabled=true
# sobe o GKE de contingência na sub-rede dr. Depois, envs/dr/platform
# instala o ArgoCD, que aplica o mesmo GitOps. O runbook
# docs/operacao/runbooks/05-failover-regiao-dr.md tem a ordem completa
# (promover a réplica antes de apontar os serviços para ela).

data "terraform_remote_state" "prod" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "prod/infra"
  }
}

locals {
  prod = data.terraform_remote_state.prod.outputs
}

resource "google_sql_database_instance" "replica" {
  count = var.sql_replica_enabled ? 1 : 0

  project              = local.prod.project_id
  name                 = "${local.prod.sql_instance_name}-dr"
  region               = local.prod.dr_region
  database_version     = "POSTGRES_15"
  master_instance_name = local.prod.sql_instance_name
  deletion_protection  = var.deletion_protection

  replica_configuration {
    failover_target = false
  }

  settings {
    edition           = "ENTERPRISE"
    tier              = local.prod.sql_tier
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_autoresize   = true
    user_labels       = { component = "database-dr" }

    # A réplica entre regiões precisa estar na mesma VPC da principal.
    ip_configuration {
      ipv4_enabled    = false
      private_network = local.prod.network_id
      ssl_mode        = "ENCRYPTED_ONLY"
    }
  }
}

module "gke" {
  source = "../../../modules/gke"
  count  = var.cluster_enabled ? 1 : 0

  project_id          = local.prod.project_id
  name                = "solidarytech-dr"
  region              = local.prod.dr_region
  node_locations      = var.node_locations
  network             = local.prod.network_id
  subnetwork          = local.prod.dr_subnet_name
  pods_range_name     = "pods"
  services_range_name = "services"
  master_authorized_cidrs = {
    nos-dr = "10.30.0.0/20"
  }
  min_nodes_per_zone  = 1
  max_nodes_per_zone  = 1
  deletion_protection = var.deletion_protection
  labels              = { component = "kubernetes-dr" }
}
