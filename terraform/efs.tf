# EFS File System for Grader
# This replaces the problematic EBS volume with ReadWriteMany support

resource "aws_efs_file_system" "omegaup_grader" {
  creation_token = "omegaup-grader"
  encrypted      = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name = "omegaup-grader-efs"
  }
}

# Mount targets in each availability zone for high availability
resource "aws_efs_mount_target" "omegaup_grader_az_a" {
  file_system_id  = aws_efs_file_system.omegaup_grader.id
  subnet_id       = aws_subnet.omegaup_eks_cluster_subnet_private_a.id
  security_groups = [aws_security_group.efs_grader.id]
}

resource "aws_efs_mount_target" "omegaup_grader_az_b" {
  file_system_id  = aws_efs_file_system.omegaup_grader.id
  subnet_id       = aws_subnet.omegaup_eks_cluster_subnet_private_b.id
  security_groups = [aws_security_group.efs_grader.id]
}

# Security group for EFS
resource "aws_security_group" "efs_grader" {
  name        = "omegaup-grader-efs-sg"
  description = "Security group for EFS grader file system"
  vpc_id      = aws_vpc.omegaup_eks_cluster_vpc.id

  ingress {
    description = "NFS from EKS nodes"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    security_groups = [
      aws_security_group.eks_cluster_sg_omegaup_eks_cluster_ClusterSharedNodeSecurityGroup.id,
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "omegaup-grader-efs-sg"
  }
}

# StorageClass for EFS
resource "kubernetes_storage_class" "efs" {
  metadata {
    name = "efs-sc"
  }
  storage_provisioner = "efs.csi.aws.com"
  parameters = {
    provisioningMode = "efs-ap"
    fileSystemId     = aws_efs_file_system.omegaup_grader.id
    directoryPerms   = "700"
  }
}

# Output EFS ID for migration scripts
output "efs_grader_id" {
  value = aws_efs_file_system.omegaup_grader.id
}
