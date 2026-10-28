# ============================================
# Rede: VPC, sub-redes (produção e DR), Cloud NAT e PSA
# ============================================
# Uma VPC só, com uma sub-rede por região. A sub-rede de DR fica pronta na
# mesma VPC porque a réplica do Cloud SQL em outra região precisa usar a
# mesma rede privada da instância principal. Os nós do GKE são privados:
# saem para a internet (Docker Hub, Datadog) só pelo Cloud NAT.

resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = var.name
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
}

resource "google_compute_subnetwork" "region" {
  for_each = var.subnets

  project                  = var.project_id
  name                     = "${var.name}-${each.key}"
  region                   = each.value.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = each.value.nodes_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = each.value.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = each.value.services_cidr
  }
}

resource "google_compute_router" "region" {
  for_each = var.subnets

  project = var.project_id
  name    = "${var.name}-${each.key}"
  region  = each.value.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "region" {
  for_each = var.subnets

  project                            = var.project_id
  name                               = "${var.name}-${each.key}"
  router                             = google_compute_router.region[each.key].name
  region                             = each.value.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Private Service Access: faixa reservada na VPC para os serviços gerenciados
# (Cloud SQL) receberem IP privado. Serve as duas regiões.
resource "google_compute_global_address" "psa" {
  project       = var.project_id
  name          = "${var.name}-psa"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = split("/", var.psa_cidr)[0]
  prefix_length = tonumber(split("/", var.psa_cidr)[1])
  network       = google_compute_network.this.id
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.this.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa.name]

  # Sem ABANDON, o destroy falha enquanto o Google ainda guarda recursos
  # (ex.: instância do Cloud SQL em exclusão) na conexão.
  deletion_policy = "ABANDON"
}
