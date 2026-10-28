# Consumidos por envs/prod/platform (terraform_remote_state), pelo CI
# (variáveis do GitHub) e por deploy/gitops/scripts/configurar-ambiente.sh.

output "project_id" {
  value = var.project_id
}

output "project_number" {
  value = data.google_project.this.number
}

output "region" {
  value = var.region
}

output "dr_region" {
  value = var.dr_region
}

output "cluster_name" {
  value = module.gke.name
}

output "cluster_location" {
  value = module.gke.location
}

output "cluster_dns_endpoint" {
  value = module.gke.dns_endpoint
}

output "kubectl_credentials_command" {
  value = "gcloud container clusters get-credentials ${module.gke.name} --location ${module.gke.location} --project ${var.project_id} --dns-endpoint"
}

output "registry_url" {
  description = "Prefixo das imagens (<região>-docker.pkg.dev/<projeto>/solidarytech)"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}

output "gateway_address_name" {
  value = module.edge.address_name
}

output "gateway_hostname" {
  value = module.edge.hostname
}

output "certificate_map" {
  value = module.edge.certificate_map
}

output "dr_bucket" {
  value = module.data.dr_bucket
}

output "velero_service_account" {
  value = module.workload_identity.velero_service_account
}

output "network_id" {
  value = module.network.network_id
}

output "dr_subnet_name" {
  value = module.network.subnet_names["dr"]
}

output "sql_instance_name" {
  value = module.data.sql_instance_name
}

output "sql_private_ip" {
  value = module.data.sql_private_ip
}

output "sql_tier" {
  value = var.sql_tier
}

output "database_urls" {
  value     = local.database_urls
  sensitive = true
}

output "sonarqube_jdbc_url" {
  value = "jdbc:postgresql://${module.data.sql_private_ip}:5432/sonarqube?sslmode=require"
}

output "sonarqube_db_password" {
  value     = local.sql_passwords["sonarqube"]
  sensitive = true
}

output "events_topic" {
  value = module.data.events_topic
}

output "consumer_subscription" {
  value = module.data.consumer_subscription
}

output "dlq_subscription" {
  value = module.data.dlq_subscription
}
