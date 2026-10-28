terraform {
  required_version = ">= 1.16.0"

  # Primeira execução com state local. Depois que o bucket existir, copie
  # backend.tf.example para backend.tf e rode
  #   terraform init -migrate-state -backend-config="bucket=<state_bucket>"
  # (runbook docs/operacao/runbooks/01-bootstrap-projeto-gcp.md).

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.9"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 8.9"
    }
  }
}

# user_project_override + billing_project: a API de budgets cobra a cota no
# projeto, não no usuário que roda o bootstrap.
provider "google" {
  project               = var.project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.project_id

  default_labels = {
    project     = "solidarytech"
    environment = "production"
    costcenter  = "ngo-core"
    managed-by  = "terraform"
  }
}

provider "google-beta" {
  project               = var.project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.project_id
}
