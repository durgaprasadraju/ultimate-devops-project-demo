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

  cluster_addons = local.cluster_addons

  # Exactly one compute path: managed EC2 node group OR Fargate profiles.
  eks_managed_node_groups = local.eks_managed_node_groups
  fargate_profiles        = local.fargate_profiles

  tags = var.tags

  # Ensures destroy runs: EKS → ELB/SG cleanup → VPC (public subnets must not
  # tear down while a Classic/NLB ELB still holds ENIs).
  depends_on = [null_resource.wait_for_elb_cleanup]
}
