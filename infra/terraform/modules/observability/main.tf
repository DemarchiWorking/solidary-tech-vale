# ============================================
# Datadog (SLOs, alertas, AIOps) + PagerDuty (ITSM) + ChatOps + self-heal
# ============================================
# Fluxo de um incidente:
#   Monitor dispara (taxa de 5xx > 5% ou p95 acima do limite) ou o Watchdog
#   detecta anomalia
#        ├──► @pagerduty-<serviço>              -> abre incidente
#        ├──► @webhook-discord-alerts           -> avisa o canal
#        └──► @webhook-github-selfheal-<serviço> (só 5xx) -> repository_dispatch
#             no monorepo, que roda .github/workflows/<serviço>-self-heal.yml
#             e faz `kubectl rollout restart` no GKE.
#
# As métricas trace.http.server.request.* são geradas pelo Datadog a partir
# dos traces enviados pelo OTel Collector. A distribuição de latência
# trace.http.server.request é medida em segundos.

locals {
  tags_base = ["env:production", "team:solidarytech", "project:solidarytech"]
}

# --- PagerDuty ---
data "pagerduty_user" "owner" {
  email = var.pagerduty_user_email
}

data "pagerduty_vendor" "datadog" {
  name = "Datadog"
}

resource "pagerduty_escalation_policy" "solidarytech" {
  name      = "SolidaryTech - On-call"
  num_loops = 2

  rule {
    escalation_delay_in_minutes = 10
    target {
      type = "user_reference"
      id   = data.pagerduty_user.owner.id
    }
  }
}

resource "pagerduty_service" "svc" {
  for_each          = toset(var.monitored_services)
  name              = "solidarytech-${each.value}"
  description       = "SolidaryTech - ${each.value}"
  escalation_policy = pagerduty_escalation_policy.solidarytech.id
}

resource "pagerduty_service_integration" "datadog" {
  for_each = toset(var.monitored_services)
  name     = data.pagerduty_vendor.datadog.name
  service  = pagerduty_service.svc[each.value].id
  vendor   = data.pagerduty_vendor.datadog.id
}

resource "datadog_integration_pagerduty_service_object" "svc" {
  for_each     = toset(var.monitored_services)
  service_name = each.value
  service_key  = pagerduty_service_integration.datadog[each.value].integration_key
}

# --- ChatOps: o sufixo /slack faz o Discord aceitar o payload do Slack ---
resource "datadog_webhook" "discord_alerts" {
  name      = "discord-alerts"
  url       = "${var.discord_webhook_url}/slack"
  encode_as = "json"
  payload = jsonencode({
    text = "*$ALERT_TITLE*\n$EVENT_MSG\nStatus: *$ALERT_TRANSITION* | Prioridade: $ALERT_PRIORITY\nVer no Datadog: $LINK"
  })
}

# --- Self-heal: o event_type escolhe o workflow do serviço no monorepo ---
resource "datadog_webhook" "github_selfheal" {
  for_each  = toset(var.monitored_services)
  name      = "github-selfheal-${each.value}"
  url       = "https://api.github.com/repos/${var.github_repository}/dispatches"
  encode_as = "json"

  custom_headers = jsonencode({
    Authorization = "Bearer ${var.github_selfheal_token}"
    Accept        = "application/vnd.github+json"
  })

  payload = jsonencode({
    event_type = "self-heal-${each.value}"
    client_payload = {
      service     = each.value
      alert_title = "$ALERT_TITLE"
      alert_id    = "$ID"
    }
  })
}

# --- SLI 1: taxa de erros 5xx (dispara o self-heal) ---
resource "datadog_monitor" "http_5xx_error_rate" {
  for_each = toset(var.monitored_services)

  name  = "[SolidaryTech] Taxa de erros 5xx alta - ${each.value}"
  type  = "metric alert"
  query = "sum(last_5m):( sum:trace.http.server.request.errors{service:${each.value}}.as_count() / sum:trace.http.server.request.hits{service:${each.value}}.as_count() ) * 100 > 5"

  message = <<-EOT
    {{#is_alert}}
    A taxa de erros HTTP 5xx do **${each.value}** passou de 5% nos últimos 5
    minutos e está consumindo o error budget do SLO de disponibilidade
    (99,9%). O self-heal vai executar
    `kubectl rollout restart deployment/${each.value}`.
    {{/is_alert}}
    {{#is_recovery}}
    Taxa de erros do ${each.value} normalizada (< 5%).
    {{/is_recovery}}

    @pagerduty-${each.value} @webhook-discord-alerts @webhook-github-selfheal-${each.value}
  EOT

  monitor_thresholds {
    critical = 5
  }

  notify_no_data      = false
  renotify_interval   = 10
  require_full_window = false
  tags                = concat(local.tags_base, ["service:${each.value}", "slo:availability"])

  depends_on = [
    datadog_integration_pagerduty_service_object.svc,
    datadog_webhook.discord_alerts,
    datadog_webhook.github_selfheal,
  ]
}

# --- SLI 2: latência p95 (em segundos) ---
resource "datadog_monitor" "latency_p95" {
  for_each = toset(var.monitored_services)

  name  = "[SolidaryTech] Latência p95 alta - ${each.value}"
  type  = "metric alert"
  query = "avg(last_5m):p95:trace.http.server.request{service:${each.value}} > ${var.latency_p95_threshold_seconds}"

  message = <<-EOT
    {{#is_alert}}
    A latência p95 do **${each.value}** passou de
    ${var.latency_p95_threshold_seconds * 1000} ms nos últimos 5 minutos e
    está consumindo o error budget do SLO de latência.
    {{/is_alert}}
    {{#is_recovery}}
    Latência do ${each.value} normalizada.
    {{/is_recovery}}

    @pagerduty-${each.value} @webhook-discord-alerts
  EOT

  monitor_thresholds {
    critical = var.latency_p95_threshold_seconds
  }

  notify_no_data      = false
  require_full_window = false
  tags                = concat(local.tags_base, ["service:${each.value}", "slo:latency"])

  depends_on = [
    datadog_integration_pagerduty_service_object.svc,
    datadog_webhook.discord_alerts,
  ]
}

# --- SLOs como código (janela de 30 dias) ---
resource "datadog_service_level_objective" "availability" {
  for_each = toset(var.monitored_services)

  name        = "[SolidaryTech] Disponibilidade - ${each.value}"
  type        = "metric"
  description = "Proporção de requisições sem erro 5xx."

  query {
    numerator   = "sum:trace.http.server.request.hits{service:${each.value}}.as_count() - sum:trace.http.server.request.errors{service:${each.value}}.as_count()"
    denominator = "sum:trace.http.server.request.hits{service:${each.value}}.as_count()"
  }

  thresholds {
    timeframe = "30d"
    target    = var.availability_slo_target
    warning   = var.availability_slo_warning
  }

  tags = concat(local.tags_base, ["service:${each.value}"])
}

resource "datadog_service_level_objective" "latency" {
  for_each = toset(var.monitored_services)

  name        = "[SolidaryTech] Latência p95 - ${each.value}"
  type        = "monitor"
  description = "Tempo em que o p95 ficou abaixo de ${var.latency_p95_threshold_seconds * 1000} ms."
  monitor_ids = [datadog_monitor.latency_p95[each.value].id]

  thresholds {
    timeframe = "30d"
    target    = var.latency_slo_target
  }

  tags = concat(local.tags_base, ["service:${each.value}"])
}

# --- AIOps: alerta sobre as anomalias que o Watchdog detecta sozinho ---
resource "datadog_monitor" "watchdog" {
  name  = "[SolidaryTech] Watchdog detectou anomalia"
  type  = "event-v2 alert"
  query = "events(\"source:watchdog env:production (${join(" OR ", [for s in var.monitored_services : "service:${s}"])})\").rollup(\"count\").last(\"30m\") > 0"

  message = <<-EOT
    {{#is_alert}}
    O Watchdog (AIOps do Datadog) detectou um comportamento anômalo num
    serviço da SolidaryTech antes de um alerta por limiar. Veja a história
    no Watchdog e avalie abrir incidente.
    {{/is_alert}}

    @webhook-discord-alerts
  EOT

  monitor_thresholds {
    critical = 0
  }

  notify_no_data = false
  tags           = concat(local.tags_base, ["aiops:watchdog"])

  depends_on = [datadog_webhook.discord_alerts]
}
