terraform {
  required_version = ">= 1.16.0"

  # State no bucket criado pelo bootstrap. Configuração parcial: o bucket vem
  # do backend.hcl (terraform init -backend-config=backend.hcl).
  backend "gcs" {
    prefix = "prod/infra"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.9"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  # FinOps: labels obrigatórias em todo recurso que aceita label. No GCP a
  # label só aceita minúsculas, números, "_" e "-": as tags do enunciado
  # (Project=SolidaryTech, Environment=Production, CostCenter=NGO-Core)
  # viram project=solidarytech, environment=production, costcenter=ngo-core.
  default_labels = local.labels
}
