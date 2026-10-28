variable "project_id" {
  type = string
}

variable "name" {
  description = "Nome do cluster (também prefixo da SA dos nós; até 20 caracteres)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{3,19}$", var.name))
    error_message = "Use de 4 a 20 caracteres: minúsculas, números e hífen, começando por letra."
  }
}

variable "region" {
  description = "Região do cluster regional (ex.: southamerica-east1)"
  type        = string
}

variable "node_locations" {
  description = "Zonas dos nós (o control plane é regional de qualquer forma)"
  type        = list(string)
}

variable "network" {
  type = string
}

variable "subnetwork" {
  type = string
}

variable "pods_range_name" {
  type = string
}

variable "services_range_name" {
  type = string
}

variable "master_authorized_cidrs" {
  description = "Faixas internas (nome => CIDR) autorizadas no endpoint IP privado do control plane"
  type        = map(string)
  default     = {}
}

variable "machine_type" {
  description = "Tipo de máquina do pool principal"
  type        = string
  default     = "e2-standard-2"
}

variable "min_nodes_per_zone" {
  type    = number
  default = 1
}

variable "max_nodes_per_zone" {
  type    = number
  default = 2
}

variable "disk_size_gb" {
  description = "Disco de boot de cada nó (o padrão do GKE, 100 GB, pesa na cota de SSD)"
  type        = number
  default     = 50
}

variable "spot" {
  description = "Usa VMs Spot no pool principal (bem mais barato, pode ser interrompido)"
  type        = bool
  default     = false
}

variable "release_channel" {
  type    = string
  default = "REGULAR"
}

variable "deletion_protection" {
  description = "Impede o destroy do cluster (desligue de propósito antes de destruir)"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels de FinOps aplicadas ao cluster e às VMs dos nós"
  type        = map(string)
  default     = {}
}
