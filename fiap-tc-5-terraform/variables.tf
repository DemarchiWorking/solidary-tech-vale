# ============================================
# General
# ============================================

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "postgres_location" {
  description = "Azure region for PostgreSQL (pode diferir da location principal por disponibilidade)"
  type        = string
  default     = "eastus2"
}

variable "project_name" {
  description = "Prefixo do projeto pra nomear os recursos"
  type        = string
  default     = "solidarytech"
}

variable "environment" {
  description = "Nome do ambiente (usado no nome dos recursos, minúsculo)"
  type        = string
  default     = "prod"
}

variable "deploy_databases" {
  description = "Provisiona bancos, mensageria e backend do Velero (PostgreSQL, Service Bus, Cosmos DB, Storage). Desligue para economizar enquanto só a stack de observabilidade está sendo validada."
  type        = bool
  default     = false
}

# ============================================
# AKS
# ============================================

variable "aks_min_count" {
  description = "Mínimo de nós no autoscaling do AKS"
  type        = number
  default     = 3
}

variable "aks_max_count" {
  description = "Máximo de nós no autoscaling do AKS"
  type        = number
  default     = 5
}

variable "aks_vm_size" {
  description = "SKU da VM dos nós do AKS"
  type        = string
  default     = "Standard_B2s"
}

# ============================================
# PostgreSQL
# ============================================

variable "postgres_admin_user" {
  description = "Usuário administrador do PostgreSQL"
  type        = string
  default     = "pgadmin"
}

variable "postgres_admin_password" {
  description = "Senha do administrador do PostgreSQL"
  type        = string
  sensitive   = true
  default     = ""
}

variable "postgres_sku" {
  description = "SKU do PostgreSQL Flexible Server (tier_family_cores)"
  type        = string
  default     = "B_Standard_B1ms"
}

# ============================================
# Service Bus
# ============================================

variable "servicebus_sku" {
  description = "SKU do Service Bus"
  type        = string
  default     = "Basic"
}

# ============================================
# ArgoCD
# ============================================

variable "argocd_github_token" {
  description = "Token do GitHub (fine-grained, só leitura de Contents no monorepo) para o ArgoCD ler o GitOps num repositório privado. Vazio = repositório público, sem credencial."
  type        = string
  sensitive   = true
  default     = ""
}

# ============================================
# Observabilidade / SRE / ITSM (Datadog + PagerDuty + Discord + Self-Healing)
# ============================================

variable "monitored_services" {
  description = "Microsserviços cobertos pelos Monitors do Datadog, PagerDuty e self-healing. donation-service é o obrigatório (SLO do desafio); adicione os demais se quiser cobertura completa."
  type        = list(string)
  default     = ["donation-service"]
}

variable "github_owner" {
  description = "Usuário ou organização do GitHub dono do monorepo"
  type        = string
}

variable "github_repo" {
  description = "Nome do monorepo no GitHub (serviços, GitOps e esta IaC)"
  type        = string
  default     = "solidary-tech-vale"
}

variable "service_repos" {
  description = "Sobrescreve o repositório (\"owner/repo\") de um serviço no webhook de self-healing. Por padrão todos usam o monorepo \"<github_owner>/<github_repo>\" (local.service_repos em main.tf)."
  type        = map(string)
  default     = {}
}

variable "latency_p95_threshold_ms" {
  description = "Limite de latência p95 (ms) do SLO de latência dos serviços monitorados"
  type        = number
  default     = 500
}

variable "datadog_api_key" {
  description = "Datadog API Key (Organization Settings > API Keys)"
  type        = string
  sensitive   = true
}

variable "datadog_app_key" {
  description = "Datadog Application Key (Organization Settings > Application Keys)"
  type        = string
  sensitive   = true
}

variable "datadog_site" {
  description = "Site do Datadog (datadoghq.com, datadoghq.eu, us5.datadoghq.com, etc.)"
  type        = string
  default     = "datadoghq.com"
}

variable "pagerduty_token" {
  description = "PagerDuty API Token (User Settings > API Access Keys), com permissão de leitura e escrita"
  type        = string
  sensitive   = true
}

variable "pagerduty_user_email" {
  description = "E-mail do usuário PagerDuty (dono da conta) que receberá os incidentes na escalation policy"
  type        = string
}

variable "discord_webhook_url" {
  description = "URL do Webhook do canal Discord usado para as notificações de incidente (ChatOps). Ex: https://discord.com/api/webhooks/<id>/<token>"
  type        = string
  sensitive   = true
}

variable "github_selfheal_token" {
  description = "GitHub PAT (escopo 'repo') usado pelo Datadog para disparar o repository_dispatch de self-healing nos repositórios dos serviços"
  type        = string
  sensitive   = true
}

variable "gitops_repo" {
  description = "Repositório GitOps (owner/repo) lido pelo ArgoCD e usado como fallback do self-healing. Padrão: o monorepo \"<github_owner>/<github_repo>\"."
  type        = string
  default     = null
}
