mock_provider "google" {}

variables {
  project_id          = "solidarytech-test"
  name                = "solidarytech-prod"
  region              = "southamerica-east1"
  node_locations      = ["southamerica-east1-a", "southamerica-east1-b", "southamerica-east1-c"]
  network             = "projects/solidarytech-test/global/networks/solidarytech-vpc"
  subnetwork          = "solidarytech-vpc-prod"
  pods_range_name     = "pods"
  services_range_name = "services"
  master_authorized_cidrs = {
    nos-prod = "10.10.0.0/20"
  }
  labels = { project = "solidarytech", environment = "production", costcenter = "ngo-core" }
}

run "cluster_regional_privado_e_sem_chave" {
  command = plan

  assert {
    condition     = google_container_cluster.this.location == "southamerica-east1"
    error_message = "O cluster precisa ser regional (location = região, não zona)."
  }
  assert {
    condition     = google_container_cluster.this.private_cluster_config[0].enable_private_nodes && google_container_cluster.this.private_cluster_config[0].enable_private_endpoint
    error_message = "Nós e endpoint IP do control plane precisam ser privados."
  }
  assert {
    condition     = google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].allow_external_traffic
    error_message = "O endpoint DNS precisa aceitar tráfego externo (GitHub Actions, Terraform)."
  }
  assert {
    condition     = google_container_cluster.this.workload_identity_config[0].workload_pool == "solidarytech-test.svc.id.goog"
    error_message = "Workload Identity precisa estar ligado."
  }
  assert {
    condition     = google_container_cluster.this.datapath_provider == "ADVANCED_DATAPATH"
    error_message = "Dataplane V2 (NetworkPolicy) precisa estar ligado."
  }
  assert {
    condition     = google_container_cluster.this.gateway_api_config[0].channel == "CHANNEL_STANDARD"
    error_message = "Gateway API precisa estar ligada (o GitOps usa Gateway/HTTPRoute)."
  }
  assert {
    condition     = google_container_cluster.this.master_authorized_networks_config[0].gcp_public_cidrs_access_enabled == false && length(google_container_cluster.this.master_authorized_networks_config[0].cidr_blocks) == 1
    error_message = "O endpoint IP só aceita as faixas internas autorizadas."
  }
  assert {
    condition     = google_container_cluster.this.monitoring_config[0].managed_prometheus[0].enabled == false
    error_message = "Managed Prometheus duplicaria o kube-prometheus-stack."
  }
  assert {
    condition     = google_container_cluster.this.deletion_protection
    error_message = "Produção precisa de proteção contra destroy por padrão."
  }
  assert {
    condition     = google_container_cluster.this.resource_labels["costcenter"] == "ngo-core"
    error_message = "Labels de FinOps precisam chegar ao cluster."
  }
}

run "pool_principal_enxuto_e_seguro" {
  command = plan

  assert {
    condition     = google_container_node_pool.principal.node_config[0].disk_size_gb == 50
    error_message = "Disco de 50 GB (o padrão de 100 GB pesa na cota de SSD)."
  }
  assert {
    condition     = google_container_node_pool.principal.node_config[0].workload_metadata_config[0].mode == "GKE_METADATA"
    error_message = "Os nós precisam do metadata server do GKE (Workload Identity)."
  }
  assert {
    condition     = google_container_node_pool.principal.autoscaling[0].min_node_count == 1 && google_container_node_pool.principal.autoscaling[0].max_node_count == 2
    error_message = "Autoscaling de 1 a 2 nós por zona."
  }
  assert {
    condition     = google_project_iam_member.nodes_default.role == "roles/container.defaultNodeServiceAccount"
    error_message = "A SA dos nós precisa do papel mínimo recomendado."
  }
}

run "nome_invalido_e_recusado" {
  command = plan

  variables {
    name = "Nome_Invalido"
  }

  expect_failures = [var.name]
}
