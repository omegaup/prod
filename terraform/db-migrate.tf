resource "aws_iam_policy" "rds_deploy" {
  name = "db-migrate"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "rds:ModifyDBParameterGroup",
          "rds:ResetDBParameterGroup"
        ]
        Effect = "Allow"
        Resource = [
          aws_db_parameter_group.omegaup_frontend.arn,
        ]
      },
    ]
  })

  tags = {
  }
}

data "aws_iam_policy_document" "rds_deploy_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.omegaup_eks_cluster.url, "https://", "")}:sub"
      values = [
        // This should match kubernetes_service_account.rds_deploy.metadata[0].name
        "system:serviceaccount:${kubernetes_namespace.omegaup.metadata[0].name}:db-migrate",
      ]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.omegaup_eks_cluster.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "rds_deploy" {
  name        = "db-migrate"
  description = "The role for the db-migrate service."

  assume_role_policy = data.aws_iam_policy_document.rds_deploy_assume_role_policy.json
  managed_policy_arns = [
    aws_iam_policy.rds_deploy.arn,
  ]

  tags = {
  }
}

resource "kubernetes_service_account" "rds_deploy" {
  metadata {
    name      = "db-migrate"
    namespace = kubernetes_namespace.omegaup.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.rds_deploy.arn
    }
  }
}

