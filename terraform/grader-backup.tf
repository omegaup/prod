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
    ]
  })

  tags = {
    k8s = ""
  }
}

resource "aws_iam_role" "grader_backup" {
  name        = "grader-backup"
  description = "The role for the grader-backup service."

  assume_role_policy = data.aws_iam_policy_document.omegaup_eks_cluster_assume_role_policy.json
  managed_policy_arns = [
    aws_iam_policy.grader_backup.arn,
  ]

  tags = {
    k8s = ""
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
