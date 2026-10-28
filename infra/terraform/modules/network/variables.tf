variable "project_id" {
  description = "Projeto GCP"
  type        = string
}

variable "name" {
  description = "Nome base da VPC e dos recursos de rede"
  type        = string
}

variable "subnets" {
  description = "Sub-redes por função (ex.: prod, dr), cada uma com região e faixas de nós, pods e services"
  type = map(object({
    region        = string
    nodes_cidr    = string
    pods_cidr     = string
    services_cidr = string
  }))
}

variable "psa_cidr" {
  description = "Faixa reservada para o Private Service Access (IP privado do Cloud SQL), ex.: 10.40.0.0/16"
  type        = string
  default     = "10.40.0.0/16"
}
