# --- Elastic IPs for NLB ---
# One EIP per AZ (subnet_count). Allocated once, survive terraform destroy/apply.
# DNS A-records are set to these IPs one time and never change between deploys.
#
# ⚠️ Do NOT destroy these unless rotating IPs intentionally —
#    DNS records will break if IPs change.

resource "aws_eip" "nlb" {
  count  = var.subnet_count
  domain = "vpc"

  tags = {
    Name      = "${var.project_name}-nlb-eip-${count.index}"
    ManagedBy = "terraform"
    Project   = var.project_name
    AZ        = data.aws_availability_zones.available.names[count.index]
  }
}
