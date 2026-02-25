# AIOps Phase 2 — GPU Spot Node Group
# g4dn.xlarge: 4 vCPU, 16 GB RAM, NVIDIA T4 16 GB VRAM
# KEDA + Cluster Autoscaler manage scale 0→1 on demand

resource "aws_launch_template" "aiops_node" {
  name_prefix = "${var.project_name}-aiops-node-"

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name      = "${var.project_name}-aiops-gpu-worker"
      Role      = "gpu-inference"
      Cluster   = "${var.project_name}-cluster"
      ManagedBy = "terraform"
      Project   = var.project_name
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "aiops" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-aiops-node-group"
  node_role_arn   = aws_iam_role.node_group.arn

  # Single AZ — EBS PVC must be in same AZ as GPU node
  subnet_ids = [aws_subnet.main[0].id]

  capacity_type = "SPOT"
  # Multiple GPU instance types for SPOT diversity — same T4/A10G GPU, same VRAM tier.
  # EKS picks whichever has available SPOT capacity.
  # g4dn.xlarge  : 4 vCPU, 16 GB RAM, 1x T4 16 GB VRAM
  # g4dn.2xlarge : 8 vCPU, 32 GB RAM, 1x T4 16 GB VRAM
  # g5.xlarge    : 4 vCPU, 16 GB RAM, 1x A10G 24 GB VRAM
  instance_types = ["g4dn.xlarge", "g4dn.2xlarge", "g5.xlarge"]
  ami_type       = "AL2_x86_64_GPU"

  scaling_config {
    desired_size = 0
    min_size     = 0
    max_size     = 1
  }

  taint {
    key    = "aiops"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  labels = {
    aiops = "true"
    role  = "gpu-inference"
  }

  launch_template {
    id      = aws_launch_template.aiops_node.id
    version = aws_launch_template.aiops_node.latest_version
  }

  tags = {
    Name                                                       = "${var.project_name}-aiops-node-group"
    ManagedBy                                                  = "terraform"
    Project                                                    = var.project_name
    Environment                                                = var.environment
    # Required for Cluster Autoscaler to manage this node group
    "k8s.io/cluster-autoscaler/enabled"                        = "true"
    "k8s.io/cluster-autoscaler/${var.project_name}-cluster"    = "owned"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_registry,
  ]
}
