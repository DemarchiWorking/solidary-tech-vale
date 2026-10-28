variable "project_id" {
  description = "Projeto GCP de produção"
  type        = string
}

variable "region" {
  type    = string
  default = "southamerica-east1"
}

variable "dr_region" {
  description = "Região de DR (backups, bucket do Velero, réplica do Cloud SQL)"
  type        = string
  default     = "southamerica-west1"
}

variable "node_locations" {
  type    = list(string)
  default = ["southamerica-east1-a", "southamerica-east1-b", "southamerica-east1-c"]
}

variable "node_machine_type" {
  type    = string
  default = "e2-standard-2"
}

variable "min_nodes_per_zone" {
  type    = number
  default = 1
}

variable "max_nodes_per_zone" {
  type    = number
  default = 2
}

variable "sql_tier" {
  type    = string
  default = "db-custom-1-3840"
}

variable "hostname" {
  description = "Domínio próprio (opcional). Vazio = <ip>.sslip.io"
  type        = string
  default     = ""
}

variable "ci_deployer_service_account" {
  description = "E-mail da SA ci-deployer (output do bootstrap) que publica as imagens"
  type        = string
  default     = ""
}

variable "deletion_protection" {
  description = "Protege GKE, Cloud SQL, Firestore e o bucket de DR contra destroy"
  type        = bool
  default     = true
}
