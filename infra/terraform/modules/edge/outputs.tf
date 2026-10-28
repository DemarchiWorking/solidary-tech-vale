output "address_name" {
  description = "Nome do IP global (usado no Gateway como NamedAddress)"
  value       = google_compute_global_address.gateway.name
}

output "address" {
  value = google_compute_global_address.gateway.address
}

output "hostname" {
  value = local.hostname
}

output "certificate_map" {
  description = "Mapa de certificados (anotação networking.gke.io/certmap do Gateway)"
  value       = google_certificate_manager_certificate_map.gateway.name
}

output "certificate_name" {
  value = google_certificate_manager_certificate.gateway.name
}
