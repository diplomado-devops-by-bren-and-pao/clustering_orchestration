data "aws_eks_cluster" "existing" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "existing" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.existing.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.existing.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1"
    command     = "aws"
    args = [
      "eks", "get-token",
      "--cluster-name", var.cluster_name,
      "--region", var.aws_region
    ]
  }
}

resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = var.namespace_name

    labels = {
      app         = "saludos"
      environment = var.environment
      managed-by  = "terraform"
    }

    annotations = {
      description = "Namespace para el laboratorio Kubernetes de Saludos"
    }
  }
}
