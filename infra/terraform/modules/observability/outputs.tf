output "error_rate_monitor_ids" {
  value = { for k, m in datadog_monitor.http_5xx_error_rate : k => m.id }
}

output "latency_monitor_ids" {
  value = { for k, m in datadog_monitor.latency_p95 : k => m.id }
}

output "slo_ids" {
  value = {
    availability = { for k, s in datadog_service_level_objective.availability : k => s.id }
    latency      = { for k, s in datadog_service_level_objective.latency : k => s.id }
  }
}

output "watchdog_monitor_id" {
  value = datadog_monitor.watchdog.id
}

output "pagerduty_service_urls" {
  value = { for k, s in pagerduty_service.svc : k => "https://app.pagerduty.com/service-directory/${s.id}" }
}
