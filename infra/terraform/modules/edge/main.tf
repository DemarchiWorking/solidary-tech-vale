# ============================================
# Borda: IP global, hostname sslip.io e certificado gerenciado
# ============================================
# O Gateway do GitOps (gke-l7-global-external-managed) usa este IP pelo nome
# (NamedAddress) e este mapa de certificados pela anotação
# networking.gke.io/certmap. O hostname é o próprio IP com hífens em
# <ip>.sslip.io, que resolve para o IP sem precisar de domínio próprio.
#
# Sem dns_authorizations, o certificado usa autorização por load balancer:
# o Google só emite depois que o Gateway estiver servindo HTTPS nesse IP
# com o mapa (até ~1 h). Até lá, o HTTPS não responde.

resource "google_compute_global_address" "gateway" {
  project      = var.project_id
  name         = "${var.name}-gateway-ip"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
  labels       = merge(var.labels, { component = "edge" })
}

locals {
  hostname = var.hostname != "" ? var.hostname : "${replace(google_compute_global_address.gateway.address, ".", "-")}.sslip.io"
}

resource "google_certificate_manager_certificate" "gateway" {
  project = var.project_id
  name    = "${var.name}-gateway"
  scope   = "DEFAULT"
  labels  = merge(var.labels, { component = "edge" })

  managed {
    domains = [local.hostname]
  }
}

resource "google_certificate_manager_certificate_map" "gateway" {
  project = var.project_id
  name    = "${var.name}-gateway-certmap"
  labels  = merge(var.labels, { component = "edge" })
}

resource "google_certificate_manager_certificate_map_entry" "gateway" {
  project      = var.project_id
  name         = "${var.name}-gateway-host"
  map          = google_certificate_manager_certificate_map.gateway.name
  hostname     = local.hostname
  certificates = [google_certificate_manager_certificate.gateway.id]
  labels       = merge(var.labels, { component = "edge" })
}
