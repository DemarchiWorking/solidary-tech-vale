terraform {
  required_version = ">= 1.16.0"

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
