output "name" {
  value = google_container_cluster.this.name
}

output "location" {
  value = google_container_cluster.this.location
}

output "dns_endpoint" {
  description = "Endpoint DNS do control plane (kubectl/Terraform/GitHub Actions, autenticado por IAM)"
  value       = google_container_cluster.this.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint
}

output "workload_pool" {
  description = "Pool do Workload Identity; só existe depois do cluster, por isso os bindings dependem deste output"
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "node_service_account" {
  value = google_service_account.nodes.email
}
