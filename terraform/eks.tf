module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Public endpoint so you can run kubectl/helm from the sandbox workstation.
  cluster_endpoint_public_access = true

  # Give the identity that runs `terraform apply` cluster-admin so the helm
  # and kubernetes providers can manage in-cluster resources.
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  eks_managed_node_groups = {
    workers = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.node_instance_type]

      desired_size = var.node_desired_size
      min_size     = var.node_min_size
      max_size     = var.node_max_size
    }
  }

  tags = var.tags
}
