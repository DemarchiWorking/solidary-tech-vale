variable "project_id" {
  type = string
}

variable "project_number" {
  description = "Número do projeto (o principal:// usa o número, não o ID)"
  type        = string
}

variable "name" {
  type = string
}

variable "workload_pool" {
  description = "Output workload_pool do módulo gke"
  type        = string
}

variable "apps" {
  description = "KSA de cada serviço (namespace e nome), iguais aos do GitOps"
  type = map(object({
    namespace = string
    name      = string
  }))
  default = {
    donation     = { namespace = "donation", name = "donation-service" }
    notification = { namespace = "notification", name = "notification-service" }
    volunteer    = { namespace = "volunteer", name = "volunteer-service" }
  }
}

variable "events_topic" {
  type = string
}

variable "consumer_subscription" {
  type = string
}

variable "dr_bucket" {
  type = string
}

variable "velero_namespace" {
  type    = string
  default = "velero"
}

variable "velero_ksa" {
  description = "Nome da KSA do servidor do Velero no chart 12.x"
  type        = string
  default     = "velero-server"
}
