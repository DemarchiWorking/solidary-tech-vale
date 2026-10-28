variable "monitored_services" {
  description = "Serviços com SLO, alertas, PagerDuty e self-heal. donation-service é o obrigatório (caminho crítico)."
  type        = list(string)
  default     = ["donation-service"]
}

variable "github_repository" {
  description = "Monorepo (owner/repo) que recebe o repository_dispatch do self-heal"
  type        = string
}

variable "github_selfheal_token" {
  description = "Token fine-grained com permissão de disparar repository_dispatch no monorepo"
  type        = string
  sensitive   = true
}

variable "latency_p95_threshold_seconds" {
  description = "Limite do p95 em segundos (a métrica de trace do Datadog é em segundos)"
  type        = number
  default     = 0.5
}

variable "availability_slo_target" {
  type    = number
  default = 99.9
}

variable "availability_slo_warning" {
  type    = number
  default = 99.95
}

variable "latency_slo_target" {
  type    = number
  default = 99
}

variable "pagerduty_user_email" {
  type = string
}

variable "discord_webhook_url" {
  type      = string
  sensitive = true
}
