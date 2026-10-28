variable "state_bucket" {
  type = string
}

variable "github_repository" {
  type    = string
  default = "DemarchiWorking/solidary-tech-vale"
}

variable "argocd_github_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "datadog_api_key" {
  type      = string
  sensitive = true
}

variable "selfheal_service_account" {
  type    = string
  default = ""
}
