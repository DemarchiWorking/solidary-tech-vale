# ============================================
# Virtual Network
# ============================================

resource "azurerm_virtual_network" "main" {
  name                = "vnet-${local.prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.0.0.0/16"]
  tags                = merge(local.tags, { Component = "network" })
}

# ============================================
# Subnet for AKS
# ============================================

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks-${local.prefix}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.0.0/20"]
}
