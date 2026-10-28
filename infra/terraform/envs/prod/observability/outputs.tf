output "slo_ids" {
  value = module.observability.slo_ids
}

output "watchdog_monitor_id" {
  value = module.observability.watchdog_monitor_id
}

output "pagerduty_service_urls" {
  value = module.observability.pagerduty_service_urls
}
