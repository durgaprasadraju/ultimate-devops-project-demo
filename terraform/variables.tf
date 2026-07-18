variable "region" {
  description = "AWS region for the sandbox EKS cluster."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "otel-demo"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
  default     = "1.30"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "node_instance_type" {
  description = "EC2 instance type for the managed worker nodes."
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 3
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 3
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 4
}

variable "app_namespace" {
  description = "Namespace where the application is deployed by Argo CD."
  type        = string
  default     = "otel-demo"
}

variable "git_repo_url" {
  description = "Git repository URL that Argo CD syncs the application from."
  type        = string
  default     = "https://github.com/durgaprasadraju/ultimate-devops-project-demo.git"
}

variable "git_target_revision" {
  description = "Git branch, tag, or commit that Argo CD tracks."
  type        = string
  default     = "main"
}

variable "git_manifest_path" {
  description = "Path in the repository that contains the Kubernetes manifests."
  type        = string
  default     = "kubernetes"
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    Project   = "otel-demo"
    ManagedBy = "terraform"
  }
}
