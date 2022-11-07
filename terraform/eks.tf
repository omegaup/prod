resource "aws_iam_role" "omegaup_eks_cluster" {
  name = "eksctl-omegaup-eks-cluster-cluster-ServiceRole-13X7J64PR8UED"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service : "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  inline_policy {
    name = "eksctl-omegaup-eks-cluster-cluster-PolicyCloudWatchMetrics"
    policy = jsonencode(
      {
        Statement = [
          {
            Action = [
              "cloudwatch:PutMetricData",
            ]
            Effect   = "Allow"
            Resource = "*"
          },
        ]
        Version = "2012-10-17"
      }
    )
  }
  inline_policy {
    name = "eksctl-omegaup-eks-cluster-cluster-PolicyELBPermissions"
    policy = jsonencode(
      {
        Statement = [
          {
            Action = [
              "ec2:DescribeAccountAttributes",
              "ec2:DescribeAddresses",
              "ec2:DescribeInternetGateways",
            ]
            Effect   = "Allow"
            Resource = "*"
          },
        ]
        Version = "2012-10-17"
      }
    )
  }

  tags = {
    "Name"                                        = "eksctl-omegaup-eks-cluster-cluster/ServiceRole"
    "alpha.eksctl.io/cluster-name"                = "omegaup-eks-cluster"
    "alpha.eksctl.io/eksctl-version"              = "0.55.0"
    "eksctl.cluster.k8s.io/v1alpha1/cluster-name" = "omegaup-eks-cluster"
  }
}

resource "aws_vpc" "omegaup_eks_cluster_vpc" {
  cidr_block                       = "192.168.0.0/16"
  assign_generated_ipv6_cidr_block = true

  tags = {
    Name = "omegaup-eks-cluster-vpc"
    k8s  = ""
  }
}

resource "aws_subnet" "omegaup_eks_cluster_subnet_public_a" {
  vpc_id            = aws_vpc.omegaup_eks_cluster_vpc.id
  cidr_block        = "192.168.0.0/20"
  ipv6_cidr_block   = "2600:1f18:1a8d:8100::/64"
  availability_zone = "us-east-1a"

  tags = {
    Name                     = "omegaup-eks-cluster-subnet-public-a"
    k8s                      = ""
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "omegaup_eks_cluster_subnet_public_b" {
  vpc_id            = aws_vpc.omegaup_eks_cluster_vpc.id
  cidr_block        = "192.168.16.0/20"
  ipv6_cidr_block   = "2600:1f18:1a8d:8101::/64"
  availability_zone = "us-east-1b"

  tags = {
    Name                     = "omegaup-eks-cluster-subnet-public-b"
    k8s                      = ""
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "omegaup_eks_cluster_subnet_private_a" {
  vpc_id            = aws_vpc.omegaup_eks_cluster_vpc.id
  cidr_block        = "192.168.32.0/20"
  availability_zone = "us-east-1a"

  tags = {
    Name                              = "omegaup-eks-cluster-subnet-private-a"
    k8s                               = ""
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "omegaup_eks_cluster_subnet_private_b" {
  vpc_id            = aws_vpc.omegaup_eks_cluster_vpc.id
  cidr_block        = "192.168.48.0/20"
  availability_zone = "us-east-1b"

  tags = {
    Name                              = "omegaup-eks-cluster-subnet-private-b"
    k8s                               = ""
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_security_group" "eks_cluster_sg_omegaup_eks_cluster_ClusterSharedNodeSecurityGroup" {
  name        = "eksctl-omegaup-eks-cluster-cluster-ClusterSharedNodeSecurityGroup-1RB02GC9S0ZR7"
  description = "Communication between all nodes in the cluster"
  vpc_id      = aws_vpc.omegaup_eks_cluster_vpc.id

  ingress {
    description = "Allow nodes to communicate with each other (all ports)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  // This is aws_security_group_rule.eks_cluster_sg_omegaup_eks_cluster_ClusterSharedNodeSecurityGroup_managed_ingress
  ingress {
    description = "Allow managed and unmanaged nodes to communicate with each other (all ports)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    security_groups = [
      "sg-0c245cbac36c4c54f",
    ]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name                                          = "eksctl-omegaup-eks-cluster-cluster/ClusterSharedNodeSecurityGroup"
    "alpha.eksctl.io/eksctl-version"              = "0.55.0"
    "eksctl.cluster.k8s.io/v1alpha1/cluster-name" = "omegaup-eks-cluster"
    "alpha.eksctl.io/cluster-name"                = "omegaup-eks-cluster"
  }
}

resource "aws_security_group_rule" "eks_cluster_sg_omegaup_eks_cluster_ClusterSharedNodeSecurityGroup_managed_ingress" {
  security_group_id        = aws_security_group.eks_cluster_sg_omegaup_eks_cluster_ClusterSharedNodeSecurityGroup.id
  type                     = "ingress"
  description              = "Allow managed and unmanaged nodes to communicate with each other (all ports)"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.eks_cluster_sg_omegaup_eks_cluster.id
}

resource "aws_security_group" "eks_cluster_sg_omegaup_eks_cluster" {
  name        = "eks-cluster-sg-omegaup-eks-cluster-1476032553"
  description = "EKS created security group applied to ENI that is attached to EKS Control Plane master nodes, as well as any managed workloads."
  vpc_id      = aws_vpc.omegaup_eks_cluster_vpc.id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  ingress {
    description = "Allow unmanaged nodes to communicate with control plane (all ports)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    security_groups = [
      aws_security_group.eks_cluster_sg_omegaup_eks_cluster_ClusterSharedNodeSecurityGroup.id,
    ]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name                                        = "eks-cluster-sg-omegaup-eks-cluster-1476032553"
    "kubernetes.io/cluster/omegaup-eks-cluster" = "owned"
  }
}

resource "aws_security_group" "eksctl_omegaup_eks_cluster_nodegroup_omegaup_eks_nodes_reserved" {
  name        = "eksctl-omegaup-eks-cluster-nodegroup-omegaup-eks-nodes-reserved-SG-1XZYAKIY7XIK9"
  description = "Communication between the control plane and worker nodes in group omegaup-eks-nodes-reserved"
  vpc_id      = aws_vpc.omegaup_eks_cluster_vpc.id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    "Name"                                        = "eksctl-omegaup-eks-cluster-nodegroup-omegaup-eks-nodes-reserved/SG"
    "k8s"                                         = "k8s"
    "alpha.eksctl.io/cluster-name"                = "omegaup-eks-cluster"
    "alpha.eksctl.io/eksctl-version"              = "0.71.0"
    "alpha.eksctl.io/nodegroup-name"              = "omegaup-eks-nodes-reserved"
    "alpha.eksctl.io/nodegroup-type"              = "unmanaged"
    "eksctl.cluster.k8s.io/v1alpha1/cluster-name" = "omegaup-eks-cluster"
    "eksctl.io/v1alpha2/nodegroup-name"           = "omegaup-eks-nodes-reserved"
    "kubernetes.io/cluster/omegaup-eks-cluster"   = "owned"
  }
}

resource "aws_security_group" "eksctl_omegaup_eks_cluster_cluster_ControlPlaneSecurityGroup" {
  name        = "eksctl-omegaup-eks-cluster-cluster-ControlPlaneSecurityGroup-A49RUO0BDL6V"
  description = "Communication between the control plane and worker nodegroups"
  vpc_id      = aws_vpc.omegaup_eks_cluster_vpc.id

  ingress {
    description = "Allow control plane to receive API requests from worker nodes in group omegaup-eks-nodes-reserved"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [
      aws_security_group.eksctl_omegaup_eks_cluster_nodegroup_omegaup_eks_nodes_reserved.id,
    ]
  }

  egress {
    description = "Allow control plane to communicate with worker nodes in group omegaup-eks-nodes-reserved (kubelet and workload TCP ports)"
    from_port   = 1025
    to_port     = 65535
    protocol    = "tcp"
    security_groups = [
      aws_security_group.eksctl_omegaup_eks_cluster_nodegroup_omegaup_eks_nodes_reserved.id,
    ]
  }

  egress {
    description = "Allow control plane to communicate with worker nodes in group omegaup-eks-nodes-reserved (workloads using HTTPS port, commonly used with extension API servers)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [
      aws_security_group.eksctl_omegaup_eks_cluster_nodegroup_omegaup_eks_nodes_reserved.id,
    ]
  }

  tags = {
    "Name"                                        = "eksctl-omegaup-eks-cluster-cluster/ControlPlaneSecurityGroup"
    "alpha.eksctl.io/cluster-name"                = "omegaup-eks-cluster"
    "alpha.eksctl.io/eksctl-version"              = "0.55.0"
    "eksctl.cluster.k8s.io/v1alpha1/cluster-name" = "omegaup-eks-cluster"
  }
}

resource "aws_eks_cluster" "omegaup_eks_cluster" {
  name     = "omegaup-eks-cluster"
  role_arn = aws_iam_role.omegaup_eks_cluster.arn

  vpc_config {
    endpoint_private_access = true
    security_group_ids = [
      aws_security_group.eksctl_omegaup_eks_cluster_cluster_ControlPlaneSecurityGroup.id,
    ]
    subnet_ids = [
      aws_subnet.omegaup_eks_cluster_subnet_public_a.id,
      aws_subnet.omegaup_eks_cluster_subnet_public_b.id,
      aws_subnet.omegaup_eks_cluster_subnet_private_a.id,
      aws_subnet.omegaup_eks_cluster_subnet_private_b.id,
    ]
  }

  tags = {
    k8s = ""
  }
}

data "tls_certificate" "omegaup_eks_cluster" {
  url = aws_eks_cluster.omegaup_eks_cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "omegaup_eks_cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.omegaup_eks_cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.omegaup_eks_cluster.identity[0].oidc[0].issuer

  tags = {
    "alpha.eksctl.io/cluster-name"   = "omegaup-eks-cluster"
    "alpha.eksctl.io/eksctl-version" = "0.71.0"
  }
}
