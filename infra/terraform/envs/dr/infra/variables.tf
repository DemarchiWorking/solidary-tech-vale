variable "state_bucket" {
  description = "Bucket do state (output state_bucket do bootstrap)"
  type        = string
}

variable "sql_replica_enabled" {
  description = "Réplica do Cloud SQL na região de DR (RPO de segundos para as doações)"
  type        = bool
  default     = true
}

variable "cluster_enabled" {
  description = "Sobe o GKE de contingência (deixe false fora de um failover)"
  type        = bool
  default     = false
}

variable "node_locations" {
  type    = list(string)
  default = ["southamerica-west1-a", "southamerica-west1-b"]
}

variable "deletion_protection" {
  type    = bool
  default = true
}
