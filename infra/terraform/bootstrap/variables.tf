variable "project_id" {
  description = "Projeto GCP (criado antes, com faturamento vinculado)"
  type        = string
}

variable "region" {
  type    = string
  default = "southamerica-east1"
}

variable "github_owner" {
  type    = string
  default = "DemarchiWorking"
}

variable "github_repo" {
  type    = string
  default = "solidary-tech-vale"
}

variable "github_repository_id" {
  description = "ID numérico do repositório (gh api repos/<owner>/<repo> --jq .id). Vazio = condição pelo nome."
  type        = string
  default     = ""
}

variable "github_owner_id" {
  description = "ID numérico do dono do repositório (gh api users/<owner> --jq .id)"
  type        = string
  default     = ""
}

variable "default_branch" {
  description = "Branch padrão: só ela publica imagem e roda o self-heal"
  type        = string
  default     = "main"
}

variable "billing_account" {
  description = "ID da conta de faturamento para o orçamento (vazio = sem orçamento)"
  type        = string
  default     = ""
}

variable "budget_amount" {
  type    = number
  default = 1500
}

variable "budget_currency" {
  type    = string
  default = "BRL"
}
