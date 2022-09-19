resource "aws_ebs_volume" "omegaup_grader" {
  availability_zone = "us-east-1a"
  size              = "50"
  type              = "gp2"

  tags = {
    "Name" = "omegaup-grader-pv"
  }
}

resource "kubernetes_persistent_volume" "omegaup_grader_pv" {
  metadata {
    name = "omegaup-grader-pv"
    labels = {
    }
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    persistent_volume_source {
      csi {
        driver        = "ebs.csi.aws.com"
        fs_type       = "ext4"
        volume_handle = aws_ebs_volume.omegaup_grader.id
      }
    }
    capacity = {
      storage = "${aws_ebs_volume.omegaup_grader.size}Gi"
    }
    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "topology.kubernetes.io/zone"
            operator = "In"
            values = [
              aws_ebs_volume.omegaup_grader.availability_zone,
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
    volume_mode                      = "Filesystem"
  }
}

resource "aws_iam_policy" "grader" {
  name = "grader"

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
          "arn:aws:s3:::omegaup-backup/omegaup/submissions/*",
          "arn:aws:s3:::omegaup-runs/*",
        ]
      },
    ]
  })

  tags = {
  }
}

data "aws_iam_policy_document" "grader_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.omegaup_eks_cluster.url, "https://", "")}:sub"
      values = [
        // This should match kubernetes_service_account.grader.metadata[0].name
        "system:serviceaccount:${kubernetes_namespace.omegaup.metadata[0].name}:grader",
      ]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.omegaup_eks_cluster.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "grader" {
  name        = "grader"
  description = "The role for the grader service."

  assume_role_policy = data.aws_iam_policy_document.grader_assume_role_policy.json
  managed_policy_arns = [
    aws_iam_policy.grader.arn,
  ]

  tags = {
  }
}

resource "kubernetes_service_account" "grader" {
  metadata {
    name      = "grader"
    namespace = kubernetes_namespace.omegaup.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.grader.arn
    }
  }
}

