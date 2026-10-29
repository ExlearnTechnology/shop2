variable "aws_region" {
  description = "AWS region that will host the EKS cluster and ECR repositories."
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "retail-eks"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version."
  type        = string
  default     = "1.37"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must be a Kubernetes minor version such as 1.37."
  }
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "IPv4 CIDRs allowed to reach the EKS public API endpoint. Set this to your operator IP with a /32 mask."
  type        = list(string)

  validation {
    condition = (
      length(var.cluster_endpoint_public_access_cidrs) > 0 &&
      alltrue([for cidr in var.cluster_endpoint_public_access_cidrs : can(cidrnetmask(cidr))]) &&
      !contains(var.cluster_endpoint_public_access_cidrs, "0.0.0.0/0")
    )
    error_message = "Provide at least one valid IPv4 CIDR and do not expose the EKS API to 0.0.0.0/0."
  }
}

variable "node_min_size" {
  description = "Minimum number of EKS worker nodes."
  type        = number
  default     = 2
}

variable "node_desired_size" {
  description = "Desired number of EKS worker nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of EKS worker nodes."
  type        = number
  default     = 2
}

variable "github_owner" {
  description = "GitHub user or organization that owns the Actions repository."
  type        = string
  default     = "ExlearnTechnology"

  validation {
    condition     = length(trimspace(var.github_owner)) > 0
    error_message = "github_owner must not be empty."
  }
}

variable "github_repository" {
  description = "GitHub repository name allowed to assume the ECR access role."
  type        = string
  default     = "shop2"

  validation {
    condition     = length(trimspace(var.github_repository)) > 0
    error_message = "github_repository must not be empty."
  }
}

variable "github_actions_branch" {
  description = "Branch whose GitHub Actions workflows can assume the ECR access role."
  type        = string
  default     = "main"

  validation {
    condition     = length(trimspace(var.github_actions_branch)) > 0
    error_message = "github_actions_branch must not be empty."
  }
}
