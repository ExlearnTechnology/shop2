output "vpc_id" {
  description = "ID of the EKS VPC."
  value       = aws_vpc.eks.id
}

output "public_subnet_ids" {
  description = "IDs of the two public subnets."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the two private subnets."
  value       = aws_subnet.private[*].id
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.eks.name
}

output "eks_cluster_endpoint" {
  description = "Kubernetes API endpoint for the EKS cluster."
  value       = aws_eks_cluster.eks.endpoint
}

output "eks_node_group_name" {
  description = "Name of the managed worker node group."
  value       = aws_eks_node_group.workers.node_group_name
}

output "eks_oidc_issuer" {
  description = "OIDC issuer URL for the EKS cluster."
  value       = aws_eks_cluster.eks.identity[0].oidc[0].issuer
}

output "alb_controller_role_arn" {
  description = "IAM role assumed by the AWS Load Balancer Controller."
  value       = aws_iam_role.alb_controller.arn
}

output "argocd_namespace" {
  description = "Namespace where Argo CD is installed."
  value       = "argocd"
}

output "bastion_instance_id" {
  description = "Instance ID of the Systems Manager managed EKS bastion."
  value       = aws_instance.bastion.id
}

output "bastion_public_ip" {
  description = "Public IPv4 address of the Systems Manager managed EKS bastion."
  value       = aws_instance.bastion.public_ip
}

output "github_actions_ecr_role_arn" {
  description = "IAM role ARN to configure as the GitHub Actions AWS role."
  value       = aws_iam_role.github_actions_ecr.arn
}
