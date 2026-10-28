output "grafana_admin_password" {
  value     = random_password.grafana_admin.result
  sensitive = true
}

output "sonarqube_admin_password" {
  value     = random_password.sonarqube_admin.result
  sensitive = true
}

output "argocd_initial_admin_password_command" {
  value = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
