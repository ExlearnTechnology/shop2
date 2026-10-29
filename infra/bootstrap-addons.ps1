[CmdletBinding()]
param(
    [switch] $Destroy,
    [switch] $UpdateIngress
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = (
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
)

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE."
    }
}

if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [Runtime.InteropServices.OSPlatform]::Windows
)) {
    throw "Run terraform apply from Windows PowerShell for this bootstrap."
}

$requiredEnvironment = @(
    "AWS_REGION",
    "EKS_CLUSTER_NAME"
)

foreach ($name in $requiredEnvironment) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
        throw "Required environment variable '$name' was not set by Terraform."
    }
}

$aws = $null
$awsVersion = $null
foreach ($awsCommand in Get-Command aws -All -ErrorAction Stop) {
    $candidateVersion = & $awsCommand.Source --version 2>&1
    $awsVersion = $candidateVersion
    if ($LASTEXITCODE -eq 0 -and $candidateVersion -match "aws-cli/2\.") {
        $aws = $awsCommand.Source
        break
    }
}
if (-not $aws) {
    throw @"
AWS CLI v2 is required for EKS authentication with this kubectl version.
Detected: $awsVersion
Install or update AWS CLI v2, confirm 'aws --version' reports aws-cli/2.x, then rerun terraform apply.
"@
}

$toolDirectory = Join-Path $env:LOCALAPPDATA "retail-eks-tools"
$null = New-Item -ItemType Directory -Force -Path $toolDirectory
$awsDirectory = Split-Path -Parent $aws
$env:PATH = "$awsDirectory;$toolDirectory;$env:PATH"
$kubectl = Join-Path $toolDirectory "kubectl.exe"
$helm = Join-Path $toolDirectory "helm.exe"
$kubeconfig = Join-Path $env:TEMP "retail-eks-$($env:EKS_CLUSTER_NAME)-$PID.yaml"
$loadBalancerValues = Join-Path $env:TEMP "retail-eks-alb-values-$PID.json"
$applicationValuesPath = Join-Path $env:TEMP "retail-eks-argocd-app-values-$PID.json"
$argocdIngressPath = Join-Path $env:TEMP "retail-eks-argocd-ingress-$PID.yaml"
$argocdWorkflowRbacPath = Join-Path $env:TEMP "retail-eks-argocd-workflow-rbac-$PID.yaml"

try {
    Invoke-NativeCommand -FilePath $aws -Arguments @(
        "sts", "get-caller-identity", "--output", "json"
    )

    $clusterVersion = & $aws eks describe-cluster `
        --name $env:EKS_CLUSTER_NAME `
        --region $env:AWS_REGION `
        --query "cluster.version" `
        --output text
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read the EKS Kubernetes version."
    }

    $kubectlVersion = Invoke-RestMethod `
        -Uri "https://dl.k8s.io/release/stable-$clusterVersion.txt" `
        -UseBasicParsing
    Invoke-WebRequest `
        -Uri "https://dl.k8s.io/release/$kubectlVersion/bin/windows/amd64/kubectl.exe" `
        -OutFile $kubectl `
        -UseBasicParsing

    if (-not $UpdateIngress) {
        $helmVersion = "v3.18.6"
        $helmArchive = Join-Path $env:TEMP "helm-$helmVersion-windows-amd64-$PID.zip"
        $helmExtract = Join-Path $env:TEMP "helm-$helmVersion-windows-amd64-$PID"
        Invoke-WebRequest `
            -Uri "https://get.helm.sh/helm-$helmVersion-windows-amd64.zip" `
            -OutFile $helmArchive `
            -UseBasicParsing
        Expand-Archive -LiteralPath $helmArchive -DestinationPath $helmExtract -Force
        Copy-Item `
            -LiteralPath (Join-Path $helmExtract "windows-amd64\helm.exe") `
            -Destination $helm `
            -Force
        Remove-Item -LiteralPath $helmArchive,$helmExtract -Recurse -Force
    }

    Invoke-NativeCommand -FilePath $aws -Arguments @(
        "eks", "update-kubeconfig",
        "--name", $env:EKS_CLUSTER_NAME,
        "--region", $env:AWS_REGION,
        "--kubeconfig", $kubeconfig
    )
    $kubeconfigContent = Get-Content -Raw -LiteralPath $kubeconfig
    if ($kubeconfigContent -match "client\.authentication\.k8s\.io/v1alpha1") {
        throw @"
The selected AWS CLI generated a kubeconfig using the removed ExecCredential v1alpha1 API.
Detected: $awsVersion
Update AWS CLI to a current v2 release, confirm 'aws --version' reports aws-cli/2.x, then rerun terraform apply.
"@
    }
    $env:KUBECONFIG = $kubeconfig

    if ($UpdateIngress) {
        if ([string]::IsNullOrWhiteSpace($env:ARGOCD_ALLOWED_CIDRS)) {
            throw "ARGOCD_ALLOWED_CIDRS must be provided when updating the Argo CD ingress."
        }

        Invoke-NativeCommand -FilePath $kubectl -Arguments @(
            "annotate",
            "ingress",
            "argocd-server",
            "--namespace",
            "argocd",
            "--overwrite",
            "alb.ingress.kubernetes.io/inbound-cidrs=$($env:ARGOCD_ALLOWED_CIDRS)"
        )
        Write-Host "Updated Argo CD ingress allowlist to $($env:ARGOCD_ALLOWED_CIDRS)."
        return
    }

    if ($Destroy) {
        & $helm uninstall retail-store-app --namespace argocd --wait --timeout 15m
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Argo CD application release was not installed or could not be removed."
        }

        & $kubectl delete namespace retail-store --ignore-not-found=true --wait=true --timeout=20m
        if ($LASTEXITCODE -ne 0) {
            throw "Could not remove the retail-store namespace and its ALB ingress."
        }

        & $kubectl delete ingress argocd-server --namespace argocd `
            --ignore-not-found=true --wait=true --timeout=20m
        if ($LASTEXITCODE -ne 0) {
            throw "Could not remove the Argo CD ingress while the load balancer controller is available."
        }

        $targetGroupBindings = & $kubectl get targetgroupbindings.elbv2.k8s.aws `
            --namespace argocd --output name
        if ($LASTEXITCODE -ne 0) {
            throw "Could not inspect Argo CD target group bindings."
        }
        if ($targetGroupBindings) {
            & $kubectl wait --for=delete --namespace argocd `
                $targetGroupBindings --timeout=20m
            if ($LASTEXITCODE -ne 0) {
                throw "Could not remove Argo CD target group bindings while the load balancer controller is available."
            }
        }

        & $helm uninstall argocd --namespace argocd --wait --timeout 15m
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Argo CD release was not installed or could not be removed."
        }

        & $helm uninstall aws-load-balancer-controller --namespace kube-system --wait --timeout 10m
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "AWS Load Balancer Controller release was not installed or could not be removed."
        }

        & $kubectl delete namespace argocd --ignore-not-found=true --wait=true --timeout=10m
        if ($LASTEXITCODE -ne 0) {
            throw "Could not remove the Argo CD namespace."
        }

        return
    }

    foreach ($name in @(
        "EKS_NODE_GROUP_NAME",
        "EKS_VPC_ID",
        "ALB_CONTROLLER_ROLE_ARN",
        "ALB_CONTROLLER_CHART_VERSION",
        "ARGOCD_CHART_VERSION",
        "ARGOCD_APPS_CHART_VERSION",
        "GITHUB_REPOSITORY_URL",
        "GITHUB_BRANCH",
        "ARGOCD_ALLOWED_CIDRS"
    )) {
        if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
            throw "Required environment variable '$name' was not set by Terraform."
        }
    }

    Invoke-NativeCommand -FilePath $aws -Arguments @(
        "eks", "wait", "cluster-active",
        "--name", $env:EKS_CLUSTER_NAME,
        "--region", $env:AWS_REGION
    )
    Invoke-NativeCommand -FilePath $aws -Arguments @(
        "eks", "wait", "nodegroup-active",
        "--cluster-name", $env:EKS_CLUSTER_NAME,
        "--nodegroup-name", $env:EKS_NODE_GROUP_NAME,
        "--region", $env:AWS_REGION
    )

    Invoke-NativeCommand -FilePath $kubectl -Arguments @(
        "wait", "--for=condition=Ready", "nodes", "--all", "--timeout=15m"
    )

    $albValues = @{
        clusterName   = $env:EKS_CLUSTER_NAME
        region        = $env:AWS_REGION
        vpcId          = $env:EKS_VPC_ID
        ingressClass   = "alb"
        serviceAccount = @{
            create      = $true
            name        = "aws-load-balancer-controller"
            annotations = @{
                "eks.amazonaws.com/role-arn" = $env:ALB_CONTROLLER_ROLE_ARN
            }
        }
    } | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText(
        $loadBalancerValues,
        $albValues,
        [System.Text.UTF8Encoding]::new($false)
    )

    Invoke-NativeCommand -FilePath $helm -Arguments @(
        "upgrade", "--install", "aws-load-balancer-controller",
        "aws-load-balancer-controller",
        "--repo", "https://aws.github.io/eks-charts",
        "--version", $env:ALB_CONTROLLER_CHART_VERSION,
        "--namespace", "kube-system",
        "--values", $loadBalancerValues,
        "--wait",
        "--timeout", "15m"
    )
    Invoke-NativeCommand -FilePath $kubectl -Arguments @(
        "rollout", "status", "deployment/aws-load-balancer-controller",
        "--namespace", "kube-system",
        "--timeout=10m"
    )

    Invoke-NativeCommand -FilePath $helm -Arguments @(
        "upgrade", "--install", "argocd", "argo-cd",
        "--repo", "https://argoproj.github.io/argo-helm",
        "--version", $env:ARGOCD_CHART_VERSION,
        "--namespace", "argocd",
        "--create-namespace",
        "--set", "configs.params.server\.insecure=true",
        "--wait",
        "--timeout", "20m"
    )

    $argocdIngressManifest = @"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/healthcheck-protocol: HTTP
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
    alb.ingress.kubernetes.io/inbound-cidrs: "$($env:ARGOCD_ALLOWED_CIDRS)"
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
"@
    [System.IO.File]::WriteAllText(
        $argocdIngressPath,
        $argocdIngressManifest,
        [System.Text.UTF8Encoding]::new($false)
    )
    Invoke-NativeCommand -FilePath $kubectl -Arguments @(
        "apply", "--filename", $argocdIngressPath
    )

    $applicationValuesObject = @{
        applications = @{
            "retail-store" = @{
                namespace = "argocd"
                project   = "default"
                source    = @{
                    repoURL        = $env:GITHUB_REPOSITORY_URL
                    targetRevision = $env:GITHUB_BRANCH
                    path           = "charts/retail-store"
                }
                destination = @{
                    server    = "https://kubernetes.default.svc"
                    namespace = "retail-store"
                }
                syncPolicy = @{
                    syncOptions = @("CreateNamespace=true")
                }
            }
        }
    }
    $applicationValuesJson = $applicationValuesObject | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText(
        $applicationValuesPath,
        $applicationValuesJson,
        [System.Text.UTF8Encoding]::new($false)
    )

    Invoke-NativeCommand -FilePath $helm -Arguments @(
        "upgrade", "--install", "retail-store-app", "argocd-apps",
        "--repo", "https://argoproj.github.io/argo-helm",
        "--version", $env:ARGOCD_APPS_CHART_VERSION,
        "--namespace", "argocd",
        "--values", $applicationValuesPath,
        "--wait",
        "--timeout", "10m"
    )

    $argocdWorkflowRbacManifest = @"
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: github-actions-argocd-sync
  namespace: argocd
rules:
  - apiGroups: ["argoproj.io"]
    resources: ["applications"]
    resourceNames: ["retail-store"]
    verbs: ["get", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: github-actions-argocd-sync
  namespace: argocd
subjects:
  - kind: Group
    name: github-actions-argocd-sync
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: github-actions-argocd-sync
  apiGroup: rbac.authorization.k8s.io
"@
    [System.IO.File]::WriteAllText(
        $argocdWorkflowRbacPath,
        $argocdWorkflowRbacManifest,
        [System.Text.UTF8Encoding]::new($false)
    )
    Invoke-NativeCommand -FilePath $kubectl -Arguments @(
        "apply", "--filename", $argocdWorkflowRbacPath
    )

    $deadline = (Get-Date).AddMinutes(5)
    do {
        $applicationJson = & $kubectl get application retail-store `
            --namespace argocd `
            --output json 2>$null

        if ($LASTEXITCODE -eq 0) {
            Write-Host "Argo CD application resource is registered."
            break
        }

        if ((Get-Date) -ge $deadline) {
            throw "Timed out waiting for the retail-store Argo CD application to be registered."
        }

        Start-Sleep -Seconds 5
    } while ($true)

    $ingressDeadline = (Get-Date).AddMinutes(15)
    do {
        $ingressAddress = & $kubectl get ingress argocd-server `
            --namespace argocd `
            --output "jsonpath={.status.loadBalancer.ingress[0].hostname}" 2>$null

        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($ingressAddress)) {
            Write-Host "Argo CD URL (HTTP, restricted to $($env:ARGOCD_ALLOWED_CIDRS)): http://$ingressAddress"
            break
        }

        if ((Get-Date) -ge $ingressDeadline) {
            throw "Timed out waiting for the Argo CD public ALB address."
        }

        Start-Sleep -Seconds 15
    } while ($true)
}
finally {
    Remove-Item -LiteralPath $loadBalancerValues,$applicationValuesPath,$argocdIngressPath,$argocdWorkflowRbacPath,$kubeconfig `
        -Force `
        -ErrorAction SilentlyContinue
}
