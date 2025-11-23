provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  host                   = var.k8s_cluster_endpoint
  cluster_ca_certificate = base64decode(var.k8s_cluster_ca_certificate)
  token                  = var.k8s_cluster_token
}

