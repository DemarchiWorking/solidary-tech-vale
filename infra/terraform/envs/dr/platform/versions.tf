terraform {
  required_version = ">= 1.16.0"

  backend "gcs" {
    prefix = "dr/platform"
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
  project = local.prod.project_id
  region  = local.prod.dr_region
}

data "google_client_config" "this" {}

provider "kubernetes" {
  host  = "https://${local.dr.cluster_dns_endpoint}"
  token = data.google_client_config.this.access_token
}

provider "helm" {
  kubernetes = {
    host  = "https://${local.dr.cluster_dns_endpoint}"
    token = data.google_client_config.this.access_token
  }
}
