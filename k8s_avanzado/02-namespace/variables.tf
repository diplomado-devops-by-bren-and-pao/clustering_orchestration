variable "aws_region" {
  description = "Región de AWS donde existe EKS."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Nombre del clúster EKS ya creado por el proyecto 01-eks-rds."
  type        = string
  default     = "diplomado-k8s"
}

variable "namespace_name" {
  description = "Namespace que se creará para la aplicación."
  type        = string
  default     = "brendisas"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace_name)) && length(var.namespace_name) <= 63
    error_message = "El Namespace debe tener hasta 63 caracteres y usar minúsculas, números y guiones."
  }
}

variable "environment" {
  description = "Entorno identificado en las Labels del Namespace."
  type        = string
  default     = "dev"
}
