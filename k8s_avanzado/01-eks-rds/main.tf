data "aws_vpc" "existing" {
  id = var.vpc_id
}

data "aws_subnet" "private" {
  for_each = toset(var.private_subnet_ids)
  id       = each.value
}

data "aws_subnet" "public" {
  for_each = toset(var.public_subnet_ids)
  id       = each.value
}

data "aws_internet_gateway" "existing" {
  internet_gateway_id = var.internet_gateway_id
}

data "aws_nat_gateway" "existing" {
  id    = var.nat_gateway_id
  state = "available"
}

data "aws_route_table" "private" {
  for_each  = toset(var.private_subnet_ids)
  subnet_id = each.value
}

data "aws_route_table" "public" {
  for_each  = toset(var.public_subnet_ids)
  subnet_id = each.value
}

data "aws_security_group" "additional_nodes" {
  for_each = toset(var.additional_node_security_group_ids)
  id       = each.value
}

data "aws_security_group" "db" {
  id = var.db_security_group_id
}

data "aws_secretsmanager_secret" "rds_credentials" {
  name = var.rds_secret_name
}

data "aws_secretsmanager_secret_version" "rds_credentials" {
  secret_id = data.aws_secretsmanager_secret.rds_credentials.id
}

locals {
  private_subnet_ids = [for subnet_id in var.private_subnet_ids : data.aws_subnet.private[subnet_id].id]
  public_subnet_ids  = [for subnet_id in var.public_subnet_ids : data.aws_subnet.public[subnet_id].id]
  extra_node_sg_ids  = [for sg in data.aws_security_group.additional_nodes : sg.id]
  rds_credentials    = jsondecode(data.aws_secretsmanager_secret_version.rds_credentials.secret_string)

  common_tags = {
    Project     = var.cluster_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.26.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id                   = data.aws_vpc.existing.id
  subnet_ids               = local.private_subnet_ids
  control_plane_subnet_ids = local.private_subnet_ids

  endpoint_public_access       = true
  endpoint_private_access      = true
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  enable_cluster_creator_admin_permissions = true

  addons = {
    coredns = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
  }

  eks_managed_node_groups = {
    general = {
      name           = "${var.cluster_name}-general"
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.node_instance_types
      subnet_ids     = local.private_subnet_ids

      min_size     = var.node_count
      max_size     = var.node_count
      desired_size = var.node_count

      labels = {
        workload    = "general"
        environment = "development"
      }

      vpc_security_group_ids = [data.aws_security_group.db.id]
    }
  }

  tags = local.common_tags
}

resource "aws_db_subnet_group" "rds" {
  name        = "${var.db_identifier}-subnets"
  description = "Private subnets for the Saludos PostgreSQL database"
  subnet_ids  = local.private_subnet_ids

  tags = local.common_tags
}

resource "aws_db_instance" "saludos" {
  identifier     = var.db_identifier
  engine         = "postgres"
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = local.rds_credentials.username
  password = local.rds_credentials.password
  port     = 5432

  allocated_storage     = 20
  max_allocated_storage = 30
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [data.aws_security_group.db.id]
  publicly_accessible    = false

  backup_retention_period    = 0
  auto_minor_version_upgrade = true
  apply_immediately          = true
  deletion_protection        = false
  skip_final_snapshot        = true

  tags = merge(local.common_tags, { Name = var.db_identifier })
}
