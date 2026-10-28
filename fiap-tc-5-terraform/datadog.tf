# ============================================
# Datadog - Alertas Inteligentes + ChatOps + Self-Healing (SRE / ITSM)
# ============================================
# Fluxo:
#   Monitor dispara (taxa de erros 5xx > 5% — é o SLI de erro do SLO do
#   donation-service, ver relatório de SRE)
#        │
#        ├──► @pagerduty-<service>        -> abre incidente no PagerDuty
#        ├──► @webhook-discord-alerts     -> notifica o canal do Discord
#        └──► @webhook-github-selfheal-<service> -> repository_dispatch no
#             GitHub, que roda .github/workflows/self-heal.yml no repo do
#             serviço e executa `kubectl rollout restart deployment/<service>`
#             no AKS.
#
# AIOps (Watchdog): não existe resource do provider Terraform pra "ativar"
# o Watchdog — ele é automático assim que há dados de APM/infra fluindo pra
# conta. A evidência (Watchdog Insights detectando anomalia) é mostrada ao
# vivo no vídeo, direto na UI do Datadog.

# --- Integração com PagerDuty (uma "Service Object" por microsserviço) ---
resource "datadog_integration_pagerduty_service_object" "svc" {
  for_each     = toset(var.monitored_services)
  service_name = each.value
  service_key  = pagerduty_service_integration.datadog[each.value].integration_key
}

# --- ChatOps: notificação detalhada no Discord ---
# O sufixo "/slack" no webhook do Discord faz o Discord aceitar o payload no
# formato do Slack (compatibilidade nativa), que é o formato suportado pelo
# campo `payload` do datadog_webhook.
resource "datadog_webhook" "discord_alerts" {
  name      = "discord-alerts"
  url       = "${var.discord_webhook_url}/slack"
  encode_as = "json"
  payload = jsonencode({
    text = "🚨 *$ALERT_TITLE*\n$EVENT_MSG\nStatus: *$ALERT_TRANSITION* | Prioridade: $ALERT_PRIORITY\nVer no Datadog: $LINK"
  })
}

# --- Self-Healing: dispara o workflow do GitHub Actions (repository_dispatch) ---
# Um webhook por serviço, apontando para o repositório do PRÓPRIO
# microsserviço (diferente da Fase 4, onde o workflow morava no repo do
# GitOps) — cada serviço da SolidaryTech tem seu próprio repositório.
resource "datadog_webhook" "github_selfheal" {
  for_each  = toset(var.monitored_services)
  name      = "github-selfheal-${each.value}"
  url       = "https://api.github.com/repos/${lookup(local.service_repos, each.value, local.gitops_repo)}/dispatches"
  encode_as = "json"

  custom_headers = jsonencode({
    Authorization = "Bearer ${var.github_selfheal_token}"
    Accept        = "application/vnd.github+json"
  })

  payload = jsonencode({
    event_type = "self-heal"
    client_payload = {
      service     = each.value
      alert_title = "$ALERT_TITLE"
      alert_id    = "$ID"
    }
  })
}

# --- Alerta Inteligente: taxa de erros HTTP 5xx > 5% (SLI de erro / SLO) ---
# Métricas trace.<operation_name>.{hits,errors} são geradas automaticamente
# pelo Datadog a partir dos traces recebidos via OTel Collector (exporter
# "datadog"), agregadas por tag "service". Para spans HTTP server (otelhttp
# / auto-instrumentação Python), o operation_name é "http.server.request",
# logo a métrica é "trace.http.server.request.{hits,errors}" — NÃO
# "trace.http.server.{hits,errors}" (bug real que já pegamos na Fase 4:
# sem o ".request" a métrica não existe e o monitor fica em "No Data" pra
# sempre). Confirme em Metrics Explorer caso a operação HTTP raiz tenha
# outro nome.
resource "datadog_monitor" "http_5xx_error_rate" {
  for_each = toset(var.monitored_services)

  name  = "[SolidaryTech] Taxa de erros 5xx alta - ${each.value}"
  type  = "metric alert"
  query = "sum(last_5m):( sum:trace.http.server.request.errors{service:${each.value}}.as_count() / sum:trace.http.server.request.hits{service:${each.value}}.as_count() ) * 100 > 5"

  message = <<-EOT
    {{#is_alert}}
    🔥 A taxa de erros HTTP 5xx do **${each.value}** está acima de 5% nos
    últimos 5 minutos — viola o SLO de disponibilidade (99.9% de sucesso).
    Isso pode indicar falha silenciosa (ex.: dependência fora do ar,
    exaustão de recursos).

    Ação automática: o self-healing vai executar
    `kubectl rollout restart deployment/${each.value}` para tentar mitigar.
    {{/is_alert}}
    {{#is_recovery}}
    ✅ Taxa de erros do ${each.value} normalizada (< 5%).
    {{/is_recovery}}

    @pagerduty-${each.value} @webhook-discord-alerts @webhook-github-selfheal-${each.value}
  EOT

  monitor_thresholds {
    critical = 5
  }

  notify_no_data      = false
  renotify_interval   = 10
  require_full_window = false

  tags = [
    "service:${each.value}",
    "env:production",
    "team:solidarytech",
    "fase:5",
  ]

  depends_on = [
    datadog_integration_pagerduty_service_object.svc,
    datadog_webhook.discord_alerts,
    datadog_webhook.github_selfheal,
  ]
}

# --- Latência (2º SLI do donation-service, além da taxa de erro) ---
resource "datadog_monitor" "latency_p95" {
  for_each = toset(var.monitored_services)

  name  = "[SolidaryTech] Latência p95 alta - ${each.value}"
  type  = "metric alert"
  query = "avg(last_5m):p95:trace.http.server.request{service:${each.value}} > ${var.latency_p95_threshold_ms}"

  message = <<-EOT
    {{#is_alert}}
    ⏱️ A latência p95 do **${each.value}** está acima de
    ${var.latency_p95_threshold_ms}ms nos últimos 5 minutos — viola o SLO
    de latência.
    {{/is_alert}}
    {{#is_recovery}}
    ✅ Latência do ${each.value} normalizada.
    {{/is_recovery}}

    @pagerduty-${each.value} @webhook-discord-alerts
  EOT

  monitor_thresholds {
    critical = var.latency_p95_threshold_ms
  }

  notify_no_data      = false
  require_full_window = false

  tags = [
    "service:${each.value}",
    "env:production",
    "team:solidarytech",
    "fase:5",
    "slo:latency",
  ]

  depends_on = [
    datadog_integration_pagerduty_service_object.svc,
    datadog_webhook.discord_alerts,
  ]
}
