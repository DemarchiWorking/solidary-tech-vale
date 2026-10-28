output "network_id" {
  description = "ID da VPC (projects/<p>/global/networks/<nome>)"
  value       = google_compute_network.this.id
}

output "network_name" {
  value = google_compute_network.this.name
}

output "subnet_names" {
  description = "Nome da sub-rede por função (prod, dr)"
  value       = { for k, s in google_compute_subnetwork.region : k => s.name }
}

output "pods_range_name" {
  value = "pods"
}

output "services_range_name" {
  value = "services"
}

output "psa_connection" {
  description = "Conexão do Private Service Access (para dependência explícita do Cloud SQL)"
  value       = google_service_networking_connection.psa.id
}
