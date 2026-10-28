mock_provider "google" {}

variables {
  project_id = "solidarytech-test"
  name       = "solidarytech-vpc"
  subnets = {
    prod = { region = "southamerica-east1", nodes_cidr = "10.10.0.0/20", pods_cidr = "10.16.0.0/14", services_cidr = "10.20.0.0/20" }
    dr   = { region = "southamerica-west1", nodes_cidr = "10.30.0.0/20", pods_cidr = "10.32.0.0/14", services_cidr = "10.36.0.0/20" }
  }
}

run "uma_vpc_com_subrede_e_nat_por_regiao" {
  command = plan

  assert {
    condition     = length(google_compute_subnetwork.region) == 2 && length(google_compute_router_nat.region) == 2
    error_message = "Uma sub-rede e um Cloud NAT por região (prod e dr)."
  }
  assert {
    condition     = google_compute_subnetwork.region["dr"].region == "southamerica-west1"
    error_message = "A sub-rede de DR fica na região secundária, na mesma VPC."
  }
  assert {
    condition     = alltrue([for s in google_compute_subnetwork.region : s.private_ip_google_access])
    error_message = "Nós privados precisam de Private Google Access."
  }
}

run "psa_para_o_cloud_sql" {
  command = plan

  assert {
    condition     = google_compute_global_address.psa.address == "10.40.0.0" && google_compute_global_address.psa.prefix_length == 16
    error_message = "Faixa do Private Service Access (10.40.0.0/16)."
  }
  assert {
    condition     = google_service_networking_connection.psa.deletion_policy == "ABANDON"
    error_message = "Sem ABANDON, o destroy da conexão falha."
  }
}
