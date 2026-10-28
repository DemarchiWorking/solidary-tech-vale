terraform {
  required_version = ">= 1.16.0"

  backend "gcs" {
    prefix = "dr/infra"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.9"
    }
  }
}

provider "google" {
  project = local.prod.project_id
  region  = local.prod.dr_region

  default_labels = {
    project     = "solidarytech"
    environment = "dr"
    costcenter  = "ngo-core"
    managed-by  = "terraform"
  }
}
