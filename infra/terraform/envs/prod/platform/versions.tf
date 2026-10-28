terraform {
  required_version = ">= 1.16.0"

  backend "gcs" {
    prefix = "prod/platform"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.9"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.4"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "google" {
  project = local.infra.project_id
  region  = local.infra.region
}

data "google_client_config" "this" {}

# Endpoint DNS do control plane, autenticado com o token do próprio
# Terraform (IAM). Sem cluster_ca_certificate: esse endpoint apresenta um
# certificado de CA pública do Google, e o CA do cluster quebraria o TLS.
provider "kubernetes" {
  host  = "https://${local.infra.cluster_dns_endpoint}"
  token = data.google_client_config.this.access_token
}

provider "helm" {
  kubernetes = {
    host  = "https://${local.infra.cluster_dns_endpoint}"
    token = data.google_client_config.this.access_token
  }
}
