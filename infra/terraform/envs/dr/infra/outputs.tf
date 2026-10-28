output "sql_replica_name" {
  value = var.sql_replica_enabled ? google_sql_database_instance.replica[0].name : null
}

output "sql_replica_private_ip" {
  value = var.sql_replica_enabled ? google_sql_database_instance.replica[0].private_ip_address : null
}

output "cluster_dns_endpoint" {
  value = var.cluster_enabled ? module.gke[0].dns_endpoint : null
}

output "promote_replica_command" {
  description = "Promove a réplica a instância principal (passo 1 do failover)"
  value       = var.sql_replica_enabled ? "gcloud sql instances promote-replica ${google_sql_database_instance.replica[0].name} --project ${local.prod.project_id}" : null
}
