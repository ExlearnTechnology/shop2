resource "aws_iam_openid_connect_provider" "eks" {
  url            = aws_eks_cluster.eks.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]

  tags = {
    Name = "${var.cluster_name}-oidc-provider"
  }
}

data "aws_iam_policy_document" "alb_controller_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "${var.cluster_name}-alb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume_role.json

  tags = {
    Name = "${var.cluster_name}-alb-controller-role"
  }
}

data "aws_iam_policy_document" "alb_controller" {
  statement {
    sid       = "CreateLoadBalancerServiceLinkedRole"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    sid    = "DescribeLoadBalancerResources"
    effect = "Allow"
    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeCoipPools",
      "ec2:DescribeIpamPools",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:GetCoipPoolUsage",
      "ec2:GetSecurityGroupsForVpc",
      "acm:DescribeCertificate",
      "acm:ListCertificates",
      "cognito-idp:DescribeUserPoolClient",
      "iam:GetServerCertificate",
      "iam:ListServerCertificates",
      "shield:CreateProtection",
      "shield:DeleteProtection",
      "shield:DescribeProtection",
      "shield:GetSubscriptionState",
      "waf-regional:AssociateWebACL",
      "waf-regional:DisassociateWebACL",
      "waf-regional:GetWebACL",
      "waf-regional:GetWebACLForResource",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "wafv2:GetWebACL",
      "wafv2:GetWebACLForResource",
      "elasticloadbalancing:DescribeCapacityReservation",
      "elasticloadbalancing:DescribeListenerAttributes",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:DescribeTrustStores",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetHealth",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManageLoadBalancerSecurityGroups"
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:RevokeSecurityGroupIngress",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "TagLoadBalancerSecurityGroups"
    effect = "Allow"
    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["arn:aws:ec2:*:*:security-group/*"]
  }

  statement {
    sid    = "CreateLoadBalancersAndListeners"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:SetRulePriorities",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ManageTaggedLoadBalancers"
    effect = "Allow"
    actions = [
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:ModifyCapacityReservation",
      "elasticloadbalancing:ModifyIpPools",
      "elasticloadbalancing:ModifyListenerAttributes",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:SetWebAcl",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "alb_controller" {
  name        = "${var.cluster_name}-alb-controller-policy"
  description = "Permissions for the AWS Load Balancer Controller in ${var.cluster_name}."
  policy      = data.aws_iam_policy_document.alb_controller.json
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

resource "terraform_data" "cluster_addons" {
  input = {
    aws_region   = var.aws_region
    cluster_name = var.cluster_name
  }

  triggers_replace = [
    aws_eks_cluster.eks.endpoint,
    aws_eks_node_group.workers.id,
    aws_iam_role.alb_controller.arn,
    aws_vpc.eks.id,
    filesha256("${path.module}/bootstrap-addons.ps1"),
    var.github_owner,
    var.github_repository,
    var.github_actions_branch,
    "1.14.0",
    "10.11.6",
    "2.0.7",
  ]

  provisioner "local-exec" {
    interpreter = [
      "PowerShell",
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy",
      "Bypass",
      "-Command",
    ]

    command = "& '${path.module}/bootstrap-addons.ps1'"

    environment = {
      AWS_REGION                   = var.aws_region
      EKS_CLUSTER_NAME             = var.cluster_name
      EKS_NODE_GROUP_NAME          = aws_eks_node_group.workers.node_group_name
      EKS_VPC_ID                   = aws_vpc.eks.id
      ALB_CONTROLLER_ROLE_ARN      = aws_iam_role.alb_controller.arn
      ALB_CONTROLLER_CHART_VERSION = "1.14.0"
      ARGOCD_CHART_VERSION         = "10.11.6"
      ARGOCD_APPS_CHART_VERSION    = "2.0.7"
      GITHUB_REPOSITORY_URL        = "https://github.com/${var.github_owner}/${var.github_repository}.git"
      GITHUB_BRANCH                = var.github_actions_branch
      ARGOCD_ALLOWED_CIDRS         = join(",", var.argocd_ingress_allowed_cidrs)
    }
  }

  provisioner "local-exec" {
    when = destroy

    interpreter = [
      "PowerShell",
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy",
      "Bypass",
      "-Command",
    ]

    command = "& '${path.module}/bootstrap-addons.ps1' -Destroy"

    environment = {
      AWS_REGION       = self.input.aws_region
      EKS_CLUSTER_NAME = self.input.cluster_name
    }
  }

  depends_on = [
    aws_eks_addon.coredns,
    aws_eks_addon.kube_proxy,
    aws_eks_addon.vpc_cni,
    aws_eks_addon.ebs_csi,
    aws_eks_node_group.workers,
    aws_iam_role_policy_attachment.alb_controller,
  ]
}

resource "terraform_data" "argocd_ingress_access" {
  input = {
    aws_region    = var.aws_region
    cluster_name  = var.cluster_name
    allowed_cidrs = join(",", var.argocd_ingress_allowed_cidrs)
  }

  triggers_replace = [
    aws_eks_cluster.eks.endpoint,
    jsonencode(var.argocd_ingress_allowed_cidrs),
    filesha256("${path.module}/bootstrap-addons.ps1"),
  ]

  provisioner "local-exec" {
    interpreter = [
      "PowerShell",
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy",
      "Bypass",
      "-Command",
    ]

    command = "& '${path.module}/bootstrap-addons.ps1' -UpdateIngress"

    environment = {
      AWS_REGION           = self.input.aws_region
      EKS_CLUSTER_NAME     = self.input.cluster_name
      ARGOCD_ALLOWED_CIDRS = self.input.allowed_cidrs
    }
  }

  depends_on = [terraform_data.cluster_addons]
}
