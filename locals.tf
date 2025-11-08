locals {
  # Resource naming
  resource_prefix = "${var.project_name}-${var.environment}"

  # Common labels for all resources
  common_labels = merge(
    var.tags,
    {
      "project"     = var.project_name
      "environment" = var.environment
    }
  )

  # Consul configuration
  consul_retry_join = [var.bastion_private_ip]

  # Network configuration helpers
  private_network_cidr = var.network_cidr
}
