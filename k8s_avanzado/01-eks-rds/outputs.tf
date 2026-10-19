output "cluster_name" {
  description = "Nombre del clúster EKS."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint de la API de Kubernetes."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Versión de Kubernetes del clúster."
  value       = module.eks.cluster_version
}

output "vpc_id_used" {
  description = "VPC existente utilizada por EKS y RDS."
  value       = data.aws_vpc.existing.id
}

output "private_subnet_ids_used" {
  description = "Subnets privadas existentes utilizadas por EKS y RDS."
  value       = local.private_subnet_ids
}

output "public_subnet_ids_read" {
  description = "Subnets públicas existentes consultadas para validación y futuros balanceadores."
  value       = local.public_subnet_ids
}

output "internet_gateway_id_read" {
  description = "Internet Gateway existente consultado por data."
  value       = data.aws_internet_gateway.existing.id
}

output "nat_gateway_id_read" {
  description = "NAT Gateway existente consultado por data."
  value       = data.aws_nat_gateway.existing.id
}

output "private_route_table_ids_read" {
  description = "Route tables asociadas a las subnets privadas consultadas por data."
  value       = { for subnet_id, rt in data.aws_route_table.private : subnet_id => rt.id }
}

output "public_route_table_ids_read" {
  description = "Route tables asociadas a las subnets públicas consultadas por data."
  value       = { for subnet_id, rt in data.aws_route_table.public : subnet_id => rt.id }
}

output "additional_node_security_group_ids_read" {
  description = "Security Groups opcionales existentes que se adjuntan a los nodos."
  value       = local.extra_node_sg_ids
}

output "node_security_group_id_created_by_eks_module" {
  description = "Security Group de nodos creado y gestionado por el módulo EKS."
  value       = module.eks.node_security_group_id
}

output "rds_endpoint" {
  description = "Endpoint privado de PostgreSQL."
  value       = aws_db_instance.saludos.address
}

output "rds_port" {
  description = "Puerto de PostgreSQL."
  value       = aws_db_instance.saludos.port
}

output "rds_database_name" {
  description = "Nombre de la base de datos creada."
  value       = aws_db_instance.saludos.db_name
}

output "kubeconfig_command" {
  description = "Comando para configurar kubectl."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
