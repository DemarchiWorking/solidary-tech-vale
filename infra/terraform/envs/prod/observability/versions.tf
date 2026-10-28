terraform {
  required_version = ">= 1.16.0"

  backend "gcs" {
    prefix = "prod/observability"
  }

  required_providers {
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

provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
  api_url = "https://api.${var.datadog_site}/"
}

provider "pagerduty" {
  token = var.pagerduty_token
}
