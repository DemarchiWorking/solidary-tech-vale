# ============================================
# PagerDuty - Gerenciamento de Incidentes (ITSM)
# ============================================
# Cria, por microsserviço monitorado, um Service no PagerDuty com uma
# integração "Datadog" (Events API v2), cujo integration_key é usado pelo
# Datadog Monitor (datadog.tf) para abrir incidentes automaticamente
# (via @pagerduty-<service> na mensagem do monitor).

# Usuário já existente na conta PagerDuty (criado no cadastro da conta
# free/trial), usado como alvo da escalation policy.
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
  description       = "SolidaryTech - ${each.value} (Fase 5 - Hackathon)"
  escalation_policy = pagerduty_escalation_policy.solidarytech.id
}

resource "pagerduty_service_integration" "datadog" {
  for_each = toset(var.monitored_services)
  name     = data.pagerduty_vendor.datadog.name
  service  = pagerduty_service.svc[each.value].id
  vendor   = data.pagerduty_vendor.datadog.id
}
