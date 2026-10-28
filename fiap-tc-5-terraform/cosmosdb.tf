# ============================================
# Azure Cosmos DB - Table API (substitui o AWS DynamoDB do código original)
# ============================================
# Uma conta, duas tabelas: volunteer-service grava o cadastro de
# voluntários; notification-service grava o registro de cada notificação
# processada a partir da fila de doações (evidência do consumo/tracing
# assíncrono).
#
# FinOps — otimização aplicada (não só recomendada): modo **Serverless**
# em vez de throughput provisionado fixo. Com 400 RU/s provisionados por
# tabela (800 RU/s total), o custo é fixo em ~US$46,72/mês
# INDEPENDENTE do uso real. No volume de tráfego deste projeto (milhares
# de requisições/mês, não milhões), o modo serverless cobra só pelas RUs
# realmente consumidas (US$0,25 por milhão de RUs) — na prática, poucos
# centavos por mês. Trade-off aceito: serverless tem teto de 5.000 RU/s e
# 50GB por container (bem acima do necessário aqui) e não suporta
# geo-replicação multi-região (não usamos — só 1 `geo_location`).
resource "azurerm_cosmosdb_account" "main" {
  count               = var.deploy_databases ? 1 : 0
  name                = "cosmos-${local.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  tags                = merge(local.tags, { Component = "nosql" })

  capabilities {
    name = "EnableTable"
  }

  capabilities {
    name = "EnableServerless"
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

resource "azurerm_cosmosdb_table" "volunteers" {
  count               = var.deploy_databases ? 1 : 0
  name                = "Volunteers"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main[0].name

  # Sem `throughput`: contas serverless não aceitam RU/s provisionado por
  # container, só cobrança por consumo real.
}

resource "azurerm_cosmosdb_table" "donation_notifications" {
  count               = var.deploy_databases ? 1 : 0
  name                = "DonationNotifications"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main[0].name
}
