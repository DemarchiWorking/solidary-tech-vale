# ============================================
# Azure Container Registry (ACR)
# ============================================

resource "azurerm_container_registry" "acr" {
  name                = replace("acr${local.prefix}", "-", "")
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = true
  tags                = merge(local.tags, { Component = "acr" })
}

# ============================================
# AKS Cluster
# ============================================

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-${local.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = local.prefix
  tags                = merge(local.tags, { Component = "aks" })

  default_node_pool {
    name    = "default"
    vm_size = var.aks_vm_size
    # Lição da Fase 4: nós B2s (2 vCPU/4GB) sob pressão de memória com a
    # stack completa (ArgoCD + ingress + observabilidade + Velero + 4
    # serviços) chegaram a derrubar o kubelet. min_count = 3 já nasce com
    # folga em vez de escalar reativamente sob incidente.
    auto_scaling_enabled = true
    min_count            = var.aks_min_count
    max_count            = var.aks_max_count
    vnet_subnet_id       = azurerm_subnet.aks.id
  }

  # Mantém o gerenciamento clássico/manual de node pools (via este mesmo
  # bloco `default_node_pool` acima), sem habilitar o Node Auto
  # Provisioning (NAP/Karpenter) — argumento passou a ser obrigatório em
  # azurerm >= 4.x mesmo quando não se quer usar o modo automático.
  node_provisioning_profile {
    mode               = "Manual"
    default_node_pools = "None"
  }

  identity {
    type = "SystemAssigned"
  }

  oidc_issuer_enabled = true

  network_profile {
    network_plugin = "azure"
    network_policy = "calico"
    service_cidr   = "172.16.0.0/16"
    dns_service_ip = "172.16.0.10"
  }
}

# Grant AKS pull access to ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}
