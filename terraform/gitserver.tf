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
