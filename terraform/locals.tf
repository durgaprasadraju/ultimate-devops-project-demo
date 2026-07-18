locals {
  use_ec2          = var.compute_type == "ec2"
  use_fargate      = var.compute_type == "fargate"
  argocd_namespace = "argocd"

  # CoreDNS must run on Fargate when there are no EC2 nodes.
  cluster_addons = merge(
    {
      coredns = local.use_fargate ? {
        configuration_values = jsonencode({
          computeType = "Fargate"
        })
      } : {}
    },
    # vpc-cni and kube-proxy are DaemonSets — only useful on EC2 nodes.
    local.use_ec2 ? {
      kube-proxy = {}
      vpc-cni    = {}
    } : {}
  )

  eks_managed_node_groups = local.use_ec2 ? {
    workers = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.node_instance_type]

      desired_size = var.node_desired_size
      min_size     = var.node_min_size
      max_size     = var.node_max_size
    }
  } : {}

  # Fargate profiles cover CoreDNS, Argo CD, AWS LB Controller, and the shop.
  fargate_profiles = local.use_fargate ? {
    kube_system = {
      selectors = [
        { namespace = "kube-system" }
      ]
    }
    argocd = {
      selectors = [
        { namespace = local.argocd_namespace }
      ]
    }
    app = {
      selectors = [
        { namespace = var.app_namespace }
      ]
    }
  } : {}
}
