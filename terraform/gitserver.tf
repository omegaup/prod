resource "aws_ebs_volume" "omegaup_backend" {
  availability_zone = "us-east-1a"
  size              = "100"
  type              = "gp2"

  tags = {
    "Name"                                      = "omegaup-backend-pv"
    "kubernetes.io/cluster/omegaup-eks-cluster" = "owned"
    "kubernetes.io/created-for/pv/name"         = "pvc-2131c99a-5c2a-472f-aee8-5835b0506fc4"
    "kubernetes.io/created-for/pvc/name"        = "omegaup-backend-pvc"
    "kubernetes.io/created-for/pvc/namespace"   = "omegaup"
  }
}

resource "kubernetes_persistent_volume" "omegaup_backend_pv" {
  metadata {
    name = "omegaup-backend-pv"
    labels = {
    }
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    persistent_volume_source {
      aws_elastic_block_store {
        fs_type   = "ext4"
        volume_id = "aws://${aws_ebs_volume.omegaup_backend.availability_zone}/${aws_ebs_volume.omegaup_backend.id}"
      }
    }
    capacity = {
      storage = "${aws_ebs_volume.omegaup_backend.size}Gi"
    }
    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "topology.kubernetes.io/zone"
            operator = "In"
            values = [
              aws_ebs_volume.omegaup_backend.availability_zone,
            ]
          }
          match_expressions {
            key      = "topology.kubernetes.io/region"
            operator = "In"
            values   = ["us-east-1"]
          }
        }
      }
    }
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "gp2-retain"
    volume_mode                      = "Filesystem"
  }
}

resource "aws_s3_bucket" "omegaup_problems" {
  bucket = "omegaup-problems"

  tags = {
  }
}

resource "aws_s3_bucket_acl" "omegaup_problems" {
  bucket = aws_s3_bucket.omegaup_problems.id
  acl    = "private"
}

resource "aws_iam_policy" "gitserver" {
  name = "gitserver"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:s3:::omegaup-problems/*",
        ]
      },
    ]
  })

  tags = {
  }
}

data "aws_iam_policy_document" "gitserver_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.omegaup_eks_cluster.url, "https://", "")}:sub"
      values = [
        // This should match kubernetes_service_account.gitserver.metadata[0].name
        "system:serviceaccount:${kubernetes_namespace.omegaup.metadata[0].name}:gitserver",
      ]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.omegaup_eks_cluster.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "gitserver" {
  name        = "gitserver"
  description = "The role for the gitserver service."

  assume_role_policy = data.aws_iam_policy_document.gitserver_assume_role_policy.json
  managed_policy_arns = [
    aws_iam_policy.gitserver.arn,
  ]

  tags = {
  }
}

resource "kubernetes_service_account" "gitserver" {
  metadata {
    name      = "gitserver"
    namespace = kubernetes_namespace.omegaup.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.gitserver.arn
    }
  }
}
