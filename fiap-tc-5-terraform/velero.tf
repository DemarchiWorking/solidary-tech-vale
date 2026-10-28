# ============================================
# Disaster Recovery — Backend do Velero (Opção A do desafio)
# ============================================
# Provisiona só o BACKEND de armazenamento e as credenciais que o Velero
# (instalado via GitOps, ver addons/velero no repo fiap-tc-5-gitops) precisa
# pra fazer backup do estado do cluster (manifestos via Blob Storage +
# volumes via snapshot de Azure Disk) pra fora do cluster.

resource "azurerm_storage_account" "velero" {
  count                    = var.deploy_databases ? 1 : 0
  name                     = replace("stvelero${local.prefix}", "-", "")
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = merge(local.tags, { Component = "disaster-recovery" })
}

resource "azurerm_storage_container" "velero_backups" {
  count                 = var.deploy_databases ? 1 : 0
  name                  = "velero-backups"
  storage_account_id    = azurerm_storage_account.velero[0].id
  container_access_type = "private"
}

# --- Service Principal dedicado do Velero ---
# Precisa de permissão de ARM (não só de Storage) porque o backup de
# volumes é feito via snapshot nativo de Azure Disk, que é uma operação a
# nível de Resource Group, não de Storage Account.
data "azuread_client_config" "current" {}

resource "azuread_application" "velero" {
  count        = var.deploy_databases ? 1 : 0
  display_name = "sp-velero-${local.prefix}"
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "velero" {
  count     = var.deploy_databases ? 1 : 0
  client_id = azuread_application.velero[0].client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal_password" "velero" {
  count                = var.deploy_databases ? 1 : 0
  service_principal_id = azuread_service_principal.velero[0].id
}

# Permissão pra ler/gravar blobs de backup (manifestos do cluster).
#
# "Storage Blob Data Contributor" (só data-plane) NÃO é suficiente: o
# plugin oficial do Azure pro Velero autentica no Blob Storage via Shared
# Key, e pra obter essa chave ele chama a API de control-plane do ARM
# `Microsoft.Storage/storageAccounts/listKeys` — que é uma permissão de
# gerenciamento do recurso, não de dado. Sem "Storage Account
# Contributor" (ou equivalente com `listKeys`), o BackupStorageLocation
# fica "Unavailable" com AuthorizationFailed — bug real encontrado na
# validação end-to-end.
resource "azurerm_role_assignment" "velero_storage" {
  count                = var.deploy_databases ? 1 : 0
  scope                = azurerm_storage_account.velero[0].id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azuread_service_principal.velero[0].object_id
}

# Permissão pra tirar snapshot dos discos (PVCs) que ficam no node resource
# group gerenciado pelo AKS (MC_...), não no resource group principal.
resource "azurerm_role_assignment" "velero_disks" {
  count                = var.deploy_databases ? 1 : 0
  scope                = azurerm_kubernetes_cluster.aks.node_resource_group_id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.velero[0].object_id
}
