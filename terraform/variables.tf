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
