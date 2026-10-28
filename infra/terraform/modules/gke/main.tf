# ============================================
# GKE Standard regional
# ============================================
# - Nós privados (sem IP público), saída pelo Cloud NAT do módulo network.
# - Control plane sem endpoint IP público: o acesso (kubectl, Terraform,
#   GitHub Actions) é pelo endpoint DNS, autenticado por IAM, que dispensa
#   lista de IPs de origem.
# - Workload Identity: os pods se autenticam no Pub/Sub, no Firestore e no
#   GCS sem chave (ver modules/workload-identity).
# - Gateway API ligada: o GKE instala as CRDs de Gateway/HTTPRoute e as
#   políticas (HealthCheckPolicy, GCPBackendPolicy) usadas no GitOps.
# - FinOps: cost allocation por namespace/label, VPA para recomendações de
#   rightsizing, logs e métricas do Cloud Logging/Monitoring só dos
#   componentes do sistema (as cargas já vão para Loki e Prometheus).

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.name}-nodes"
  display_name = "Nós do GKE ${var.name}"
}

# Papel mínimo recomendado pelo Google para a SA dos nós (logs, métricas,
# metadados). A leitura das imagens é concedida só no repositório do
# Artifact Registry, no ambiente.
resource "google_project_iam_member" "nodes_default" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.name
  location = var.region

  node_locations = var.node_locations

  network         = var.network
  subnetwork      = var.subnetwork
  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # O pool padrão é removido logo após a criação; o pool gerenciado fica em
  # google_container_node_pool.principal. Disco pequeno para não estourar a
  # cota de SSD durante a criação. O provider marca remove_default_node_pool
  # como descontinuado para clusters 1.36.4+ (lá basta omitir o pool padrão);
  # fica assim porque funciona em qualquer versão do canal REGULAR. Quando o
  # canal estiver todo acima de 1.36.4, troque por initial_node_count = 0 e
  # remova node_config e remove_default_node_pool.
  remove_default_node_pool = true
  initial_node_count       = 1
  node_config {
    disk_size_gb    = 30
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  deletion_protection = var.deletion_protection

  release_channel {
    channel = var.release_channel
  }

  datapath_provider = "ADVANCED_DATAPATH"

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
  }

  # O endpoint IP (privado) só aceita as faixas internas listadas. O endpoint
  # DNS não passa por esta lista: ele é controlado por IAM.
  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = false

    dynamic "cidr_blocks" {
      for_each = var.master_authorized_cidrs
      content {
        display_name = cidr_blocks.key
        cidr_block   = cidr_blocks.value
      }
    }
  }

  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = true
    }
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  cost_management_config {
    enabled = true
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = false
    }
  }

  addons_config {
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
    http_load_balancing {
      disabled = false
    }
  }

  maintenance_policy {
    recurring_window {
      start_time = "2026-01-03T05:00:00Z"
      end_time   = "2026-01-03T09:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  resource_labels = var.labels

  lifecycle {
    # O node_config acima só vale para o pool padrão, que é removido.
    ignore_changes = [node_config]
  }
}

resource "google_container_node_pool" "principal" {
  project  = var.project_id
  name     = "principal"
  cluster  = google_container_cluster.this.id
  location = var.region

  node_locations     = var.node_locations
  initial_node_count = var.min_nodes_per_zone

  autoscaling {
    min_node_count  = var.min_nodes_per_zone
    max_node_count  = var.max_nodes_per_zone
    location_policy = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type    = var.machine_type
    disk_size_gb    = var.disk_size_gb
    disk_type       = "pd-balanced"
    spot            = var.spot
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    resource_labels = var.labels
    labels = {
      "solidarytech/pool" = "principal"
    }
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}
