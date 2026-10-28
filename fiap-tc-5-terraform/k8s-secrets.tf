# ============================================
# Secrets do Kubernetes consumidos pelo GitOps
# ============================================
# Criados aqui, direto dos recursos que geram as credenciais, para que
# nenhuma credencial passe pelo Git (o fiap-tc-5-gitops só referencia os
# nomes dos Secrets) e sem `kubectl apply` manual. Os valores ficam no
# remote state (backend.hcl), que precisa continuar privado.
#
# Nomes, namespaces e chaves são os que os Deployments e os addons do
# GitOps esperam: mudou de um lado, mude do outro.

locals {
  # urlencode() é obrigatório: a senha pode conter caracteres reservados de
  # URI (ex.: "@", "!") que, sem escape, quebram o parser da connection
  # string (o "@" da senha vira o separador user:pass@host) — bug real
  # encontrado na validação end-to-end.
  ngo_database_url             = var.deploy_databases ? "postgres://${urlencode(var.postgres_admin_user)}:${urlencode(var.postgres_admin_password)}@${azurerm_postgresql_flexible_server.ngo[0].fqdn}:5432/ngo_db?sslmode=require" : null
  donation_database_url        = var.deploy_databases ? "postgres://${urlencode(var.postgres_admin_user)}:${urlencode(var.postgres_admin_password)}@${azurerm_postgresql_flexible_server.donation[0].fqdn}:5432/donation_db?sslmode=require" : null
  servicebus_connection_string = var.deploy_databases ? azurerm_servicebus_namespace.main[0].default_primary_connection_string : null
  cosmosdb_connection_string   = var.deploy_databases ? "DefaultEndpointsProtocol=https;AccountName=${azurerm_cosmosdb_account.main[0].name};AccountKey=${azurerm_cosmosdb_account.main[0].primary_key};TableEndpoint=https://${azurerm_cosmosdb_account.main[0].name}.table.cosmos.azure.com:443/;" : null
}

resource "kubernetes_namespace_v1" "gitops" {
  for_each = toset(["ngo", "donation", "volunteer", "notification", "monitoring", "velero"])

  metadata {
    name = each.value
  }

  # O ArgoCD também usa esses namespaces (CreateNamespace=true) e pode
  # acrescentar labels/annotations: não brigar com ele.
  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }

  depends_on = [azurerm_kubernetes_cluster.aks]
}

# --- Observabilidade (sempre) ---

resource "kubernetes_secret_v1" "datadog_api_key" {
  metadata {
    name      = "datadog-api-key"
    namespace = kubernetes_namespace_v1.gitops["monitoring"].metadata[0].name
  }

  data = {
    DD_API_KEY = var.datadog_api_key
  }
}

resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace_v1.gitops["monitoring"].metadata[0].name
  }

  data = {
    admin-user     = "admin"
    admin-password = random_password.grafana_admin.result
  }
}

# --- Bancos, mensageria e DR (só com deploy_databases = true) ---

resource "kubernetes_secret_v1" "ngo_db" {
  count = var.deploy_databases ? 1 : 0

  metadata {
    name      = "db-secrets"
    namespace = kubernetes_namespace_v1.gitops["ngo"].metadata[0].name
  }

  data = {
    ngo-database-url = local.ngo_database_url
  }
}

resource "kubernetes_secret_v1" "donation_db" {
  count = var.deploy_databases ? 1 : 0

  metadata {
    name      = "db-secrets"
    namespace = kubernetes_namespace_v1.gitops["donation"].metadata[0].name
  }

  data = {
    donation-database-url = local.donation_database_url
  }
}

resource "kubernetes_secret_v1" "donation_azure" {
  count = var.deploy_databases ? 1 : 0

  metadata {
    name      = "azure-secrets"
    namespace = kubernetes_namespace_v1.gitops["donation"].metadata[0].name
  }

  data = {
    servicebus-connection-string = local.servicebus_connection_string
  }
}

resource "kubernetes_secret_v1" "notification_azure" {
  count = var.deploy_databases ? 1 : 0

  metadata {
    name      = "azure-secrets"
    namespace = kubernetes_namespace_v1.gitops["notification"].metadata[0].name
  }

  data = {
    servicebus-connection-string = local.servicebus_connection_string
    cosmosdb-connection-string   = local.cosmosdb_connection_string
  }
}

resource "kubernetes_secret_v1" "volunteer_azure" {
  count = var.deploy_databases ? 1 : 0

  metadata {
    name      = "azure-secrets"
    namespace = kubernetes_namespace_v1.gitops["volunteer"].metadata[0].name
  }

  data = {
    cosmosdb-connection-string = local.cosmosdb_connection_string
  }
}

resource "kubernetes_secret_v1" "velero_cloud_credentials" {
  count = var.deploy_databases ? 1 : 0

  metadata {
    name      = "cloud-credentials"
    namespace = kubernetes_namespace_v1.gitops["velero"].metadata[0].name
  }

  # Formato exigido pelo velero-plugin-for-microsoft-azure: chave "cloud",
  # conteúdo no formato de variáveis de ambiente.
  data = {
    cloud = <<-EOT
      AZURE_SUBSCRIPTION_ID=${var.subscription_id}
      AZURE_TENANT_ID=${data.azuread_client_config.current.tenant_id}
      AZURE_CLIENT_ID=${azuread_application.velero[0].client_id}
      AZURE_CLIENT_SECRET=${azuread_service_principal_password.velero[0].value}
      AZURE_RESOURCE_GROUP=${azurerm_resource_group.main.name}
      AZURE_CLOUD_NAME=AzurePublicCloud
    EOT
  }
}
