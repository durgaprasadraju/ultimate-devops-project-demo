output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "region" {
  description = "AWS region of the cluster."
  value       = var.region
}

output "configure_kubectl" {
  description = "Command to point kubectl at the new cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "argocd_get_admin_password" {
  description = "Command to read the initial Argo CD admin password."
  value       = "kubectl -n ${local.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d; echo"
}

output "argocd_port_forward" {
  description = "Command to open the Argo CD UI locally."
  value       = "kubectl -n ${local.argocd_namespace} port-forward svc/argocd-server 8081:443"
}

output "app_port_forward" {
  description = "Command to open the shop UI locally once Argo CD has synced it."
  value       = "kubectl -n ${var.app_namespace} port-forward svc/opentelemetry-demo-frontendproxy 8080:8080"
}
