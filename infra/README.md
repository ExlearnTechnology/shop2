# Retail store EKS infrastructure

This Terraform configuration creates the VPC, EKS cluster and managed node
group, ECR repositories, bastion host, AWS Load Balancer Controller IAM role,
Argo CD, and the Argo CD application that watches this repository's Helm chart.
The add-ons are installed by a Windows PowerShell bootstrap during `terraform
apply`.

## Important: existing infrastructure and Terraform state

Terraform can only manage resources recorded in its state. This repository does
not include the state from the other repository that created the currently
running cluster. **Do not run `terraform apply` against that AWS account as-is**:
Terraform will attempt to create the named resources again and may fail or
conflict with the existing infrastructure.

Use this configuration in a clean environment, or first make a reviewed
migration plan to import every existing resource into this configuration's
state. Do not copy state files into Git; they can contain sensitive data.
This directory uses local state, so preserve `infra/terraform.tfstate` and
secure backups between runs. If the file is lost, Terraform will no longer know
which resources it manages. For a team or a multi-machine setup, configure a
protected remote backend before applying.

## Prerequisites

- Windows with Windows PowerShell 5.1 or later
- Terraform 1.5 or later
- AWS CLI v2 configured with credentials for an IAM principal that can create
  the required VPC, EKS, EC2, ECR, IAM, and OIDC resources
- A public IPv4 address from which you will run Terraform
- GitHub Actions enabled for `ExlearnTechnology/shop2`

The EKS public API endpoint is restricted to the CIDRs provided below. Avoid
using `0.0.0.0/0`.

## Apply

Open PowerShell in the repository root and set the current operator IP as the
only public API CIDR:

```powershell
$operatorCidr = (Invoke-RestMethod -Uri "https://checkip.amazonaws.com").Trim() + "/32"
$env:TF_VAR_cluster_endpoint_public_access_cidrs = ConvertTo-Json @($operatorCidr) -Compress
```

Review the plan before applying:

```powershell
terraform -chdir=infra init
terraform -chdir=infra fmt -check
terraform -chdir=infra validate
terraform -chdir=infra plan -out=terraform.tfplan
terraform -chdir=infra apply terraform.tfplan
```

The apply process uses the AWS CLI credentials configured on this Windows
machine. It downloads pinned Helm and the matching `kubectl` into the local
user tools directory, installs the AWS Load Balancer Controller and Argo CD,
and registers the `retail-store` Argo CD application. The initial chart values
may point to images that do not exist yet; Terraform waits for the application
resource to be registered, not for workloads to become Healthy. Run the
workflow below to build and push the images and update the chart. Argo CD then
automatically syncs and the workloads should become Healthy. No Terraform
apply has been run as part of preparing this configuration.

The cluster, two private worker subnets, two NAT gateways, and managed node
group can incur ongoing AWS charges. The bootstrap add-ons are removed by the
Terraform destroy provisioner before the cluster is deleted.

## Configure GitHub Actions and deploy

After a successful apply, add a **repository Actions variable** named
`AWS_ROLE_ARN` in **Settings > Secrets and variables > Actions > Variables**.
Set its value to:

```powershell
terraform -chdir=infra output -raw github_actions_ecr_role_arn
```

The workflow uses GitHub OIDC to assume this Terraform-created role; it does
not need long-lived AWS access-key secrets. The role trust is limited to the
configured repository and branch. `AWS_REGION` is optional because the
workflow defaults to `ap-south-1`.

Run **Build and update retail store GitOps** from the `main` branch using
**Actions > Run workflow**. The workflow builds and pushes all five images to
ECR, updates their tags in `charts/retail-store/values.yaml`, and pushes that
GitOps commit. Argo CD watches the configured repository branch and
automatically syncs the changed Helm values.

Retrieve the application ingress address after deployment:

```powershell
$kubectl = Join-Path $env:LOCALAPPDATA "retail-eks-tools\kubectl.exe"
aws eks update-kubeconfig --region ap-south-1 --name retail-eks
& $kubectl get ingress --namespace retail-store
```

To access Argo CD locally, run:

```powershell
& $kubectl port-forward --namespace argocd svc/argocd-server 8080:443
```

In another PowerShell window, retrieve its initial administrator password:

```powershell
$encodedPassword = & $kubectl get secret argocd-initial-admin-secret `
  --namespace argocd `
  --output jsonpath="{.data.password}"
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedPassword))
```

Open `https://localhost:8080` and sign in as `admin`. Do not publish the
password.

## Configuration

Defaults are in `var.tf`. In particular, set
`cluster_endpoint_public_access_cidrs` for the machine that runs the
PowerShell bootstrap. Node-group minimum, desired, and maximum sizes default to
two. Keep Terraform state and its backup in protected storage; they are ignored
by Git.
