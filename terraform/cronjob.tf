resource "aws_iam_policy" "plagiarism_detector_cronjob" {
  name = "plagiarism-detector-cronjob"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.omegaup_submissions.bucket}/*",
        ]
      },
    ]
  })

  tags = {
  }
}

data "aws_iam_policy_document" "plagiarism_detector_cronjob_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.omegaup_eks_cluster.url, "https://", "")}:sub"
      values = [
        // This should match kubernetes_service_account.plagiarism_detector_cronjob.metadata[0].name
        "system:serviceaccount:${kubernetes_namespace.omegaup.metadata[0].name}:plagiarism-detector-cronjob",
      ]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.omegaup_eks_cluster.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "plagiarism_detector_cronjob" {
  name        = "plagiarism-detector-cronjob"
  description = "The role for the plagiarism_detector_cronjob service."

  assume_role_policy = data.aws_iam_policy_document.plagiarism_detector_cronjob_assume_role_policy.json
  managed_policy_arns = [
    aws_iam_policy.plagiarism_detector_cronjob.arn,
  ]

  tags = {
  }
}

resource "kubernetes_service_account" "plagiarism_detector_cronjob" {
  metadata {
    name      = "plagiarism-detector-cronjob"
    namespace = kubernetes_namespace.omegaup.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.plagiarism_detector_cronjob.arn
    }
  }
}
