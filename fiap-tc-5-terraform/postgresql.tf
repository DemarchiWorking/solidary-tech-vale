# ============================================
# PostgreSQL Flexible Servers (2 instances)
# ============================================
# backup_retention_days > 0 já habilita o PITR (Point-in-Time Restore)
# nativo do Azure Postgres Flexible Server — é o mecanismo que sustenta o
# RPO ≤ 5min do donation-service definido no PCN (ver relatório).

# 1. PostgreSQL for ngo-service
resource "azurerm_postgresql_flexible_server" "ngo" {
  count                         = var.deploy_databases ? 1 : 0
  name                          = "pg-ngo-${local.prefix}"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = var.postgres_location
  version                       = "15"
  zone                          = "1"
  administrator_login           = var.postgres_admin_user
  administrator_password        = var.postgres_admin_password
  sku_name                      = var.postgres_sku
  storage_mb                    = 32768
  backup_retention_days         = 7
  geo_redundant_backup_enabled  = false
  public_network_access_enabled = true
  tags                          = merge(local.tags, { Component = "ngo-service" })
}

resource "azurerm_postgresql_flexible_server_database" "ngo_db" {
  count     = var.deploy_databases ? 1 : 0
  name      = "ngo_db"
  server_id = azurerm_postgresql_flexible_server.ngo[0].id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "ngo_allow_azure" {
  count            = var.deploy_databases ? 1 : 0
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.ngo[0].id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# 2. PostgreSQL for donation-service (Hot Path — RPO/RTO mais rígidos)
resource "azurerm_postgresql_flexible_server" "donation" {
  count                  = var.deploy_databases ? 1 : 0
  name                   = "pg-donation-${local.prefix}"
  resource_group_name    = azurerm_resource_group.main.name
  location               = var.postgres_location
  version                = "15"
  zone                   = "1"
  administrator_login    = var.postgres_admin_user
  administrator_password = var.postgres_admin_password
  sku_name               = var.postgres_sku
  storage_mb             = 32768
  # Retenção maior no serviço crítico: mais janela de PITR disponível.
  backup_retention_days         = 14
  geo_redundant_backup_enabled  = false
  public_network_access_enabled = true
  tags                          = merge(local.tags, { Component = "donation-service", Criticality = "hot-path" })
}

resource "azurerm_postgresql_flexible_server_database" "donation_db" {
  count     = var.deploy_databases ? 1 : 0
  name      = "donation_db"
  server_id = azurerm_postgresql_flexible_server.donation[0].id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "donation_allow_azure" {
  count            = var.deploy_databases ? 1 : 0
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.donation[0].id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}
