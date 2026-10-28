output "velero_service_account" {
  description = "GSA anotada na KSA velero-server (iam.gke.io/gcp-service-account)"
  value       = google_service_account.velero.email
}

output "principals" {
  description = "Identificador principal:// de cada serviço"
  value       = local.principal
}
