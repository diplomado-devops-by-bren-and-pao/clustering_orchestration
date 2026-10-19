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

variable "kubernetes_version" {
  description = "Versión de Kubernetes disponible en EKS en la región seleccionada."
  type        = string
  default     = "1.35"
}

variable "environment" {
  description = "Etiqueta de entorno para los recursos creados."
  type        = string
  default     = "dev"
}

variable "vpc_id" {
  description = "ID de una VPC existente que Terraform consultará mediante data."
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs de al menos dos subnets privadas en AZ distintas, con salida mediante NAT o endpoints necesarios."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "Proporciona al menos dos subnets privadas para repartir el clúster entre varias zonas de disponibilidad."
  }
}

variable "public_subnet_ids" {
  description = "IDs de al menos dos subnets públicas existentes, para verificar la red y para futuros balanceadores externos."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "Proporciona al menos dos subnets públicas existentes."
  }
}

variable "internet_gateway_id" {
  description = "ID del Internet Gateway existente adjunto a la VPC. Terraform lo consulta; no lo crea ni modifica."
  type        = string
}

variable "nat_gateway_id" {
  description = "ID de un NAT Gateway público existente. Terraform lo consulta; no lo crea ni modifica."
  type        = string
}

variable "additional_node_security_group_ids" {
  description = "IDs opcionales de Security Groups existentes que se adjuntarán adicionalmente a los nodos. Deben pertenecer a la misma VPC y tener reglas compatibles con EKS."
  type        = list(string)
  default     = []
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs autorizados para acceder al endpoint público de la API EKS. Usa la IP pública administrativa con /32; no uses 0.0.0.0/0 para este laboratorio."
  type        = list(string)
}

variable "node_instance_types" {
  description = "Tipos de instancia para los nodos administrados."
  type        = list(string)
  default     = ["t3.micro"]
}

variable "node_count" {
  description = "Cantidad fija deseada de nodos para el laboratorio. Por defecto, dos nodos."
  type        = number
  default     = 2

  validation {
    condition     = var.node_count >= 2
    error_message = "Usa al menos dos nodos para practicar distribución de réplicas y disponibilidad."
  }
}

variable "rds_secret_name" {
  description = "Nombre del secreto para la RDS"
  type        = string
}

variable "db_security_group_id" {
  description = "Security Group de la instancia RDS que se creará."
  type        = string
}

variable "db_identifier" {
  description = "Identificador de la instancia RDS que se creará."
  type        = string
  default     = "saludos-postgres"
}

variable "db_name" {
  description = "Nombre de la base de datos PostgreSQL inicial."
  type        = string
  default     = "saludos"
}

variable "db_instance_class" {
  description = "Clase de instancia RDS para el laboratorio. Verifica su disponibilidad en la región elegida."
  type        = string
  default     = "db.t3.micro"
}
