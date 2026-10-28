variable "project_id" {
  type = string
}

variable "project_number" {
  description = "Número do projeto (o agente do Pub/Sub é service-<número>@gcp-sa-pubsub...)"
  type        = string
}

variable "name" {
  description = "Prefixo dos recursos (ex.: solidarytech)"
  type        = string
}

variable "region" {
  type = string
}

variable "backup_region" {
  description = "Região de DR: backups do Cloud SQL e bucket do Velero/export do Firestore"
  type        = string
}

variable "network_id" {
  description = "VPC com Private Service Access (IP privado do Cloud SQL)"
  type        = string
}

variable "sql_tier" {
  description = "Tier do Cloud SQL; HA exige núcleo dedicado (db-custom-*)"
  type        = string
  default     = "db-custom-1-3840"
}

variable "sql_availability_type" {
  description = "REGIONAL (HA com failover automático) ou ZONAL"
  type        = string
  default     = "REGIONAL"
}

variable "databases" {
  type    = list(string)
  default = ["ngo_db", "donation_db", "sonarqube"]
}

variable "sql_users" {
  description = "Usuário por serviço => banco que ele usa"
  type        = map(string)
  default = {
    ngo_app      = "ngo_db"
    donation_app = "donation_db"
    sonarqube    = "sonarqube"
  }
}

variable "events_topic" {
  type    = string
  default = "donation-events"
}

variable "consumer_subscription" {
  type    = string
  default = "notification-service"
}

variable "max_delivery_attempts" {
  description = "Tentativas antes de mover a mensagem para a DLQ"
  type        = number
  default     = 10
}

variable "firestore_location" {
  type = string
}

variable "firestore_export_schedule" {
  description = "Cron do export do Firestore para o bucket de DR"
  type        = string
  default     = "0 3 * * *"
}

variable "alert_notification_channels" {
  description = "Canais do Cloud Monitoring para o alerta de DLQ (vazio = só aparece no console)"
  type        = list(string)
  default     = []
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "labels" {
  type    = map(string)
  default = {}
}
