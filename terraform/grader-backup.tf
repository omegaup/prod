resource "aws_iam_policy" "grader_backup" {
  name = "grader-backup"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:s3:::omegaup-backup/*",
          "arn:aws:s3:::omegaup-runs/*",
        ]
      },
      {
        Action = [
          "s3:GetObject",
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:s3:::omegaup-backup/omegaup/submissions/bucket-metadata.json",
          "arn:aws:s3:::omegaup-runs/bucket-metadata.json",
        ]
      },
    ]
  })

  tags = {
  }
}

data "aws_iam_policy_document" "grader_backup_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.omegaup_eks_cluster.url, "https://", "")}:sub"
      values = [
        // This should match kubernetes_service_account.grader_backup.metadata[0].name
        "system:serviceaccount:${kubernetes_namespace.omegaup.metadata[0].name}:grader-backup",
      ]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.omegaup_eks_cluster.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "grader_backup" {
  name        = "grader-backup"
  description = "The role for the grader-backup service."

  assume_role_policy = data.aws_iam_policy_document.grader_backup_assume_role_policy.json
  managed_policy_arns = [
    aws_iam_policy.grader_backup.arn,
  ]

  tags = {
  }
}

resource "kubernetes_service_account" "grader_backup" {
  metadata {
    name      = "grader-backup"
    namespace = kubernetes_namespace.omegaup.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.grader_backup.arn
    }
  }
}
