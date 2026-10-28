variable "project_id" {
  type = string
}

variable "name" {
  type = string
}

variable "hostname" {
  description = "Domínio próprio (opcional). Vazio = <ip-com-hifens>.sslip.io"
  type        = string
  default     = ""
}

variable "labels" {
  type    = map(string)
  default = {}
}
