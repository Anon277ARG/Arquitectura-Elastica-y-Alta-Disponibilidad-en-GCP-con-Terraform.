variable "region" {
  type        = string
  description = "Region de Google Cloud"
  default     = "us-central1" #<---- las e2-micro son gratis aca
}
variable "project_id" {
  type        = string
  description = "ID del proyecto de Google Cloud"
}

variable "machine_type" {
  type        = string
  description = "Tipo de máquina a utilizar para la instancia"
  default     = "e2-micro"
}

variable "min_replicas" {
  type        = number
  description = "Cantidad mínima de instancias del MIG"
  default     = 1
}

variable "max_replicas" {
  type        = number
  description = "Cantidad máxima de instancias del MIG"
  default     = 6
}
