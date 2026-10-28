mock_provider "datadog" {}
mock_provider "pagerduty" {}

variables {
  github_repository     = "DemarchiWorking/solidary-tech-vale"
  github_selfheal_token = "t"
  pagerduty_user_email  = "oncall@example.org"
  discord_webhook_url   = "https://discord.com/api/webhooks/1/x"
}

run "latencia_em_segundos_e_slos" {
  command = plan

  assert {
    condition     = strcontains(datadog_monitor.latency_p95["donation-service"].query, "> 0.5")
    error_message = "A métrica de trace é em segundos: o limite de 500 ms é 0.5."
  }
  assert {
    condition     = datadog_service_level_objective.availability["donation-service"].thresholds[0].target == 99.9
    error_message = "SLO de disponibilidade de 99,9%."
  }
  assert {
    condition     = datadog_service_level_objective.latency["donation-service"].type == "monitor"
    error_message = "SLO de latência baseado no monitor de p95."
  }
}

run "aiops_e_selfheal" {
  command = plan

  assert {
    condition     = strcontains(datadog_monitor.watchdog.query, "source:watchdog")
    error_message = "O monitor do Watchdog (AIOps) precisa existir."
  }
  assert {
    condition     = jsondecode(datadog_webhook.github_selfheal["donation-service"].payload).event_type == "self-heal-donation-service"
    error_message = "O event_type escolhe o workflow do serviço no monorepo."
  }
  assert {
    condition     = datadog_webhook.github_selfheal["donation-service"].url == "https://api.github.com/repos/DemarchiWorking/solidary-tech-vale/dispatches"
    error_message = "O dispatch vai para o monorepo."
  }
}
