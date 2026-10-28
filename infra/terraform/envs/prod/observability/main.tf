# ============================================
# Produção — SLOs, alertas, AIOps e ITSM (Datadog + PagerDuty)
# ============================================
# Stack separada: não depende do GCP e pode ser aplicada antes do cluster
# existir (os monitores só passam a ter dados quando o tráfego começa).

module "observability" {
  source = "../../../modules/observability"

  monitored_services            = var.monitored_services
  github_repository             = var.github_repository
  github_selfheal_token         = var.github_selfheal_token
  latency_p95_threshold_seconds = var.latency_p95_threshold_seconds
  pagerduty_user_email          = var.pagerduty_user_email
  discord_webhook_url           = var.discord_webhook_url
}
