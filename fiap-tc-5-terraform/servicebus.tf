# ============================================
# Azure Service Bus (substitui o AWS SQS do código original)
# ============================================
# O donation-service publica aqui após cada doação aprovada; o
# notification-service consome pra fechar o trace distribuído assíncrono
# (mesmo padrão evaluation-service -> analytics-service da Fase 3/4).

resource "azurerm_servicebus_namespace" "main" {
  count               = var.deploy_databases ? 1 : 0
  name                = "sb-${local.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.servicebus_sku
  tags                = merge(local.tags, { Component = "messaging" })
}

resource "azurerm_servicebus_queue" "donation_events" {
  count        = var.deploy_databases ? 1 : 0
  name         = "donation-events"
  namespace_id = azurerm_servicebus_namespace.main[0].id

  max_delivery_count    = 10
  lock_duration         = "PT30S"
  max_size_in_megabytes = 1024
}
