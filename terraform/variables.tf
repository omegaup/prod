variable "aws_profile" {
  type    = string
  default = "default"
}

variable "k8s_config" {
  type    = string
  default = "~/.kube/config"
}

variable "k8s_context" {
  type    = string
  default = "default"
}

variable "az_subscription_id" {
  type    = string
  default = "9fc6c11d-9406-42f8-9a78-3813ed0875fa"
}

variable "az_runner_image" {
  type    = bool
  default = false
}
