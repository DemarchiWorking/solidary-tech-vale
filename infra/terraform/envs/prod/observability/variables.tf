variable "monitored_services" {
  type    = list(string)
  default = ["donation-service"]
}

variable "github_repository" {
  type    = string
  default = "DemarchiWorking/solidary-tech-vale"
}

variable "github_selfheal_token" {
  description = "Token fine-grained com permissão de repository_dispatch no monorepo"
  type        = string
  sensitive   = true
}

variable "latency_p95_threshold_seconds" {
  type    = number
  default = 0.5
}

variable "datadog_api_key" {
  type      = string
  sensitive = true
}

variable "datadog_app_key" {
  type      = string
  sensitive = true
}

variable "datadog_site" {
  type    = string
  default = "datadoghq.com"
}

variable "pagerduty_token" {
  type      = string
  sensitive = true
}

variable "pagerduty_user_email" {
  type = string
}

variable "discord_webhook_url" {
  type      = string
  sensitive = true
}
