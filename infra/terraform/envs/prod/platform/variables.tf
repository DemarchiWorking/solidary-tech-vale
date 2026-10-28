variable "state_bucket" {
  description = "Bucket do state (output state_bucket do bootstrap)"
  type        = string
}

variable "github_repository" {
  description = "Monorepo lido pelo ArgoCD (owner/repo)"
  type        = string
  default     = "DemarchiWorking/solidary-tech-vale"
}

variable "gitops_revision" {
  description = "HEAD = branch padrão do repositório"
  type        = string
  default     = "HEAD"
}

variable "argocd_github_token" {
  description = "Token fine-grained só de leitura (Contents: Read) no monorepo"
  type        = string
  sensitive   = true
  default     = ""
}

variable "datadog_api_key" {
  type      = string
  sensitive = true
}

variable "selfheal_service_account" {
  description = "Output ci_selfheal_service_account do bootstrap"
  type        = string
  default     = ""
}
