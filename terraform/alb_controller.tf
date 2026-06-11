# ==============================================================================
# AWS LOAD BALANCER CONTROLLER IAM ROLE & POLICY
# ==============================================================================

# Fetch the official IAM policy for the AWS Load Balancer Controller
data "http" "lbc_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json"
}

# Create the IAM policy
resource "aws_iam_policy" "lbc_policy" {
  name        = "${var.cluster_name}-AWSLoadBalancerControllerIAMPolicy"
  description = "IAM policy for AWS Load Balancer Controller"
  policy      = data.http.lbc_iam_policy.response_body
}

# Create the IAM Role for the controller utilizing Pod Identities
resource "aws_iam_role" "lbc_role" {
  name               = "${var.cluster_name}-pod-identity-aws-lbc"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "lbc_attachment" {
  policy_arn = aws_iam_policy.lbc_policy.arn
  role       = aws_iam_role.lbc_role.name
}

# Create the EKS Pod Identity Association
resource "aws_eks_pod_identity_association" "lbc_pod_identity" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lbc_role.arn

  depends_on = [module.eks]
}

# ==============================================================================
# HELM PROVIDER & RELEASE FOR AWS LOAD BALANCER CONTROLLER
# ==============================================================================

# Fetch cluster details to configure the Helm provider
data "aws_eks_cluster" "cluster" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

data "aws_eks_cluster_auth" "cluster" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# Install the AWS Load Balancer Controller via Helm
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set = [
    {
      name  = "clusterName"
      value = module.eks.cluster_name
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    }
  ]

  depends_on = [
    module.eks,
    aws_eks_pod_identity_association.lbc_pod_identity
  ]
}
