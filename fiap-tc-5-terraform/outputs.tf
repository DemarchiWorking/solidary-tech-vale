# ============================================
# AKS
# ============================================

output "aks_cluster_name" {
  description = "Nome do cluster AKS"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_kube_config_command" {
  description = "Comando pra configurar o kubectl"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.aks.name}"
}

output "aks_node_resource_group" {
  description = "Resource group gerenciado pelo AKS (VMSS, discos, load balancers) — é onde o Velero precisa de permissão pra tirar snapshot"
  value       = azurerm_kubernetes_cluster.aks.node_resource_group
}

# ------------------------------------------------------------------
# GitHub Actions self-healing (AZURE_CREDENTIALS de cada repo de serviço)
# ------------------------------------------------------------------
# Cole `azure_credentials_json` direto no secret AZURE_CREDENTIALS de cada
# um dos 4 repositórios fiap-tc-5-*-service (Settings > Secrets and
# variables > Actions). AKS_RESOURCE_GROUP = output `resource_group_name`,
# AKS_CLUSTER_NAME = output `aks_cluster_name` (mesmos valores nos 4 repos,
# é o mesmo cluster).
output "azure_credentials_json" {
  description = "JSON pronto pro secret AZURE_CREDENTIALS (azure/login@v2) dos 4 repos de serviço — formato {clientId, clientSecret, subscriptionId, tenantId}"
  sensitive   = true
  value = jsonencode({
    clientId       = azuread_application.github_selfheal.client_id
    clientSecret   = azuread_service_principal_password.github_selfheal.value
    subscriptionId = var.subscription_id
    tenantId       = data.azuread_client_config.current.tenant_id
  })
}

# ============================================
# ACR
# ============================================

output "acr_login_server" {
  description = "URL do login do ACR"
  value       = azurerm_container_registry.acr.login_server
}

output "acr_admin_username" {
  description = "Usuário admin do ACR"
  value       = azurerm_container_registry.acr.admin_username
}

output "acr_admin_password" {
  description = "Senha admin do ACR"
  value       = azurerm_container_registry.acr.admin_password
  sensitive   = true
}

# ============================================
# PostgreSQL Connection Strings
# ============================================

output "postgres_ngo_host" {
  description = "Host do PostgreSQL do ngo-service"
  value       = var.deploy_databases ? azurerm_postgresql_flexible_server.ngo[0].fqdn : null
}

output "postgres_ngo_connection_string" {
  description = "Connection string do PostgreSQL do ngo-service"
  # Montada em k8s-secrets.tf, com urlencode() no usuário e na senha.
  value     = local.ngo_database_url
  sensitive = true
}

output "postgres_donation_host" {
  description = "Host do PostgreSQL do donation-service"
  value       = var.deploy_databases ? azurerm_postgresql_flexible_server.donation[0].fqdn : null
}

output "postgres_donation_connection_string" {
  description = "Connection string do PostgreSQL do donation-service"
  value       = local.donation_database_url
  sensitive   = true
}

# ============================================
# Service Bus
# ============================================

output "servicebus_namespace" {
  description = "Namespace do Service Bus"
  value       = var.deploy_databases ? azurerm_servicebus_namespace.main[0].name : null
}

output "servicebus_connection_string" {
  description = "Connection string do Service Bus"
  value       = local.servicebus_connection_string
  sensitive   = true
}

output "servicebus_queue_name" {
  description = "Nome da fila de eventos de doação"
  value       = var.deploy_databases ? azurerm_servicebus_queue.donation_events[0].name : null
}

# ============================================
# Cosmos DB
# ============================================

output "cosmosdb_account_name" {
  description = "Nome da conta Cosmos DB"
  value       = var.deploy_databases ? azurerm_cosmosdb_account.main[0].name : null
}

output "cosmosdb_connection_string" {
  description = "Connection string do Cosmos DB (Table API)"
  value       = local.cosmosdb_connection_string
  sensitive   = true
}

output "cosmosdb_volunteers_table" {
  description = "Tabela de voluntários"
  value       = var.deploy_databases ? azurerm_cosmosdb_table.volunteers[0].name : null
}

output "cosmosdb_donation_notifications_table" {
  description = "Tabela de notificações de doação"
  value       = var.deploy_databases ? azurerm_cosmosdb_table.donation_notifications[0].name : null
}

# ============================================
# Disaster Recovery (Velero)
# ============================================

output "velero_storage_account_name" {
  description = "Storage Account de backup do Velero"
  value       = var.deploy_databases ? azurerm_storage_account.velero[0].name : null
}

output "velero_storage_container_name" {
  description = "Container de backup do Velero"
  value       = var.deploy_databases ? azurerm_storage_container.velero_backups[0].name : null
}

output "velero_storage_account_key" {
  description = "Access key do Storage Account do Velero"
  value       = var.deploy_databases ? azurerm_storage_account.velero[0].primary_access_key : null
  sensitive   = true
}

output "velero_service_principal_client_id" {
  description = "Client ID do Service Principal do Velero"
  value       = var.deploy_databases ? azuread_application.velero[0].client_id : null
}

output "velero_service_principal_client_secret" {
  description = "Client secret do Service Principal do Velero"
  value       = var.deploy_databases ? azuread_service_principal_password.velero[0].value : null
  sensitive   = true
}

output "velero_tenant_id" {
  description = "Tenant ID do Azure AD (usado no credentials file do Velero)"
  value       = data.azuread_client_config.current.tenant_id
}

# ============================================
# Resource Group
# ============================================

output "resource_group_name" {
  description = "Nome do resource group principal"
  value       = azurerm_resource_group.main.name
}

output "subscription_id" {
  description = "Assinatura Azure do ambiente (usada pelo configurar-ambiente.sh do GitOps)"
  value       = var.subscription_id
}

# ============================================
# ArgoCD
# ============================================

output "argocd_namespace" {
  description = "Namespace do ArgoCD"
  value       = helm_release.argocd.namespace
}

output "argocd_initial_admin_password_command" {
  description = "Comando pra obter a senha inicial do admin do ArgoCD"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "grafana_admin_password" {
  description = "Senha do admin do Grafana (Secret grafana-admin no namespace monitoring)"
  value       = random_password.grafana_admin.result
  sensitive   = true
}

# ============================================
# Ingress NGINX
# ============================================

output "ingress_nginx_namespace" {
  description = "Namespace do Ingress NGINX"
  value       = helm_release.ingress_nginx.namespace
}

output "ingress_nginx_get_ip_command" {
  description = "Comando pra obter o IP externo do Ingress NGINX"
  value       = "kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
}

# ============================================
# Observabilidade / SRE / ITSM
# ============================================

output "datadog_monitor_ids" {
  description = "IDs dos Datadog Monitors de taxa de erros 5xx, por serviço"
  value       = { for k, m in datadog_monitor.http_5xx_error_rate : k => m.id }
}

output "datadog_latency_monitor_ids" {
  description = "IDs dos Datadog Monitors de latência p95, por serviço"
  value       = { for k, m in datadog_monitor.latency_p95 : k => m.id }
}

output "pagerduty_escalation_policy_url" {
  description = "URL da Escalation Policy no PagerDuty"
  value       = "https://app.pagerduty.com/escalation_policies/${pagerduty_escalation_policy.solidarytech.id}"
}

output "pagerduty_service_urls" {
  description = "URLs dos Services no PagerDuty, por microsserviço"
  value       = { for k, s in pagerduty_service.svc : k => "https://app.pagerduty.com/service-directory/${s.id}" }
}
