output "grafana_admin_password" {
  value     = module.platform.grafana_admin_password
  sensitive = true
}

output "sonarqube_admin_password" {
  value     = module.platform.sonarqube_admin_password
  sensitive = true
}

output "argocd_initial_admin_password_command" {
  value = module.platform.argocd_initial_admin_password_command
}
