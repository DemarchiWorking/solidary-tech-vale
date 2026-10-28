terraform {
  required_version = ">= 1.5.0"

  # Configuração parcial: o storage account do remote state é de cada
  # assinatura, então os valores ficam fora do código, em backend.hcl
  # (gitignorado). Ver backend.hcl.example:
  #   terraform init -backend-config=backend.hcl
  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.5"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.9"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 4.21"
    }
    pagerduty = {
      source  = "PagerDuty/pagerduty"
      version = "~> 3.36"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      # Garante que `terraform destroy` não fique bloqueado caso algum
      # recurso "escape" do tracking do state (ex.: algo criado por um
      # controller do próprio AKS, como Load Balancers/Disks do
      # kube-prometheus-stack ou do Velero).
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = var.subscription_id
}

# Necessário pra criar o Service Principal do Velero (velero.tf) via Azure AD.
provider "azuread" {}

provider "helm" {
  kubernetes = {
    host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
  }
}

# Secrets que o GitOps consome (k8s-secrets.tf), com a mesma credencial do helm.
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
}

# Alertas Inteligentes (APM) + Service Map + AIOps (Watchdog): ver datadog.tf
provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
  api_url = "https://api.${var.datadog_site}/"
}

# Gerenciamento de Incidentes (ITSM): ver pagerduty.tf
provider "pagerduty" {
  token = var.pagerduty_token
}
