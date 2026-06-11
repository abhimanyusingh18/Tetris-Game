# ==============================================================================
# VARIABLES (Override these per client/environment execution)
# ==============================================================================
variable "aws_access_key" {
  description = "AWS Access Key ID"
  type        = string
  sensitive   = true
  default     = "AKIAZR2LPJMZYARP4KNG"
}

variable "aws_secret_key" {
  description = "AWS Secret Access Key"
  type        = string
  sensitive   = true
  default     = "ZFvK2SqQ/VbkH8cWUggvINGHroBivsnrxg3zpRtr"
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "Name of the EKS Cluster"
  type        = string
  default     = "abhimanyu-test-sandbox"
}

variable "environment" {
  description = "Deployment Environment Tag"
  type        = string
  default     = "test"
}

# ==============================================================================
# PROVIDER
# ==============================================================================
provider "aws" {
  region     = var.region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

# ==============================================================================
# VPC MODULE
# ==============================================================================
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "RULOANS-TEST-VPC"
  cidr = "10.0.0.0/16"

  azs             = ["${var.region}a", "${var.region}b", "${var.region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
  enable_vpn_gateway = false

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = {
    Terraform   = "true"
    Environment = var.environment
  }
}

# ==============================================================================
# EKS MODULE
# ==============================================================================
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.35"

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = concat(module.vpc.private_subnets, module.vpc.public_subnets)
  control_plane_subnet_ids = concat(module.vpc.private_subnets, module.vpc.public_subnets)

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = false

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true

  cluster_upgrade_policy = {
    support_type = "STANDARD"
  }

  eks_managed_node_groups = {
    sandbox_workers_v4 = {
      min_size       = 2
      max_size       = 5
      desired_size   = 2
      instance_types = ["t3.medium"]
      subnet_ids     = module.vpc.private_subnets
    }
  }

  cluster_addons = {
    aws-guardduty-agent       = { addon_version = "v1.15.0-eksbuild.2" }
    cert-manager              = { addon_version = "v1.20.2-eksbuild.2" }
    coredns                   = { addon_version = "v1.14.3-eksbuild.2" }
    eks-node-monitoring-agent = { addon_version = "v1.6.5-eksbuild.1" }
    eks-pod-identity-agent    = { addon_version = "v1.3.10-eksbuild.3" }
    external-dns              = { addon_version = "v0.21.0-eksbuild.4" }
    fluent-bit                = { addon_version = "v5.0.5-eksbuild.1" }
    kube-proxy                = { addon_version = "v1.35.3-eksbuild.11" }
    metrics-server            = { addon_version = "v0.8.1-eksbuild.10" }
    vpc-cni                   = { addon_version = "v1.22.1-eksbuild.2" }
  }

  tags = {
    Terraform   = "true"
    Environment = var.environment
  }
}

# ==============================================================================
# POD IDENTITY IAM ROLES & ASSOCIATIONS
# ==============================================================================
data "aws_iam_policy_document" "pod_identity_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole", "sts:TagSession"]
  }
}

# Uniquely named VPC CNI Role per cluster execution
resource "aws_iam_role" "vpc_cni_role" {
  name               = "${var.cluster_name}-pod-identity-vpc-cni"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json
}

resource "aws_iam_role_policy_attachment" "vpc_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.vpc_cni_role.name
}

resource "aws_eks_pod_identity_association" "vpc_cni" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-node"
  role_arn        = aws_iam_role.vpc_cni_role.arn

  depends_on = [module.eks]
}

# Uniquely named External DNS Role per cluster execution
resource "aws_iam_role" "external_dns_role" {
  name               = "${var.cluster_name}-pod-identity-external-dns"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json
}

resource "aws_iam_policy" "external_dns_policy" {
  name        = "${var.cluster_name}-external-dns-route53"
  description = "Allows ExternalDNS to manage Route53 records dynamically"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["route53:ChangeResourceRecordSets"],
        Resource = ["arn:aws:route53:::hostedzone/*"]
      },
      {
        Effect   = "Allow",
        Action   = ["route53:ListHostedZones", "route53:ListResourceRecordSets", "route53:ListTagsForResource"],
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "external_dns_attachment" {
  policy_arn = aws_iam_policy.external_dns_policy.arn
  role       = aws_iam_role.external_dns_role.name
}

resource "aws_eks_pod_identity_association" "external_dns" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "external-dns"
  role_arn        = aws_iam_role.external_dns_role.arn

  depends_on = [module.eks]
}
