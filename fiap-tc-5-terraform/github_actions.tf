# ============================================
# Service Principal dedicado — GitHub Actions self-healing
# ============================================
# Cada repositório de serviço (fiap-tc-5-*-service) precisa do secret
# `AZURE_CREDENTIALS` pro job `.github/workflows/self-heal.yml` (ação
# `azure/login@v2`) conseguir `az aks get-credentials` + `kubectl rollout
# restart` no AKS quando o Datadog dispara o webhook de self-healing (ver
# `datadog.tf`). Diferente da Fase 4 (onde essa credencial foi criada
# manualmente via `az ad sp create-for-rbac`, fora do Terraform), aqui ela
# é gerenciada como código — mesmo racional do SP dedicado do Velero
# (`velero.tf`): nasce e morre junto com o resto da infra, sem passo manual
# fora do `apply`.
#
# Não é gated por `var.deploy_databases`: o AKS (e portanto o self-healing)
# existe independente de bancos/mensageria/Velero estarem ligados.

resource "azuread_application" "github_selfheal" {
  display_name = "sp-github-selfheal-${local.prefix}"
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "github_selfheal" {
  client_id = azuread_application.github_selfheal.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal_password" "github_selfheal" {
  service_principal_id = azuread_service_principal.github_selfheal.id
}

# "Azure Kubernetes Service Cluster Admin Role" dá `az aks get-credentials`
# com kubeconfig de admin (contas locais do AKS), suficiente pro
# `kubectl rollout restart` do self-heal sem precisar configurar Azure AD
# RBAC dentro do Kubernetes (que este cluster não usa — ver aks.tf).
resource "azurerm_role_assignment" "github_selfheal_aks" {
  scope                = azurerm_kubernetes_cluster.aks.id
  role_definition_name = "Azure Kubernetes Service Cluster Admin Role"
  principal_id         = azuread_service_principal.github_selfheal.object_id
}
