variable "project_id" {
  type = string
}

variable "database_urls" {
  description = "URL do Postgres por serviço (ngo, donation), com sslmode=require"
  type        = map(string)
  sensitive   = true
}

variable "sonarqube_db_password" {
  type      = string
  sensitive = true
}

variable "datadog_api_key" {
  type      = string
  sensitive = true
}

variable "gitops_repo_url" {
  description = "URL https do monorepo lido pelo ArgoCD"
  type        = string
}

variable "gitops_revision" {
  description = "Revisão que o ArgoCD acompanha (HEAD = branch padrão)"
  type        = string
  default     = "HEAD"
}

variable "gitops_entry_path" {
  description = "Pasta do ponto de entrada do GitOps no monorepo"
  type        = string
  default     = "deploy/gitops/applicationsets"
}

variable "argocd_github_token" {
  description = "Token fine-grained só de leitura no monorepo (vazio = repositório público)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "argocd_chart_version" {
  type    = string
  default = "9.4.15"
}

variable "argocd_apps_chart_version" {
  type    = string
  default = "2.0.7"
}

variable "selfheal_service_account" {
  description = "E-mail da GSA usada pelo workflow de self-heal (vazio = sem RoleBinding)"
  type        = string
  default     = ""
}
