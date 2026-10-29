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
