# ============================================================================
# Hetzner Cloud Landing Zone - Main Configuration
# ============================================================================
# This file contains the core infrastructure resources for the landing zone.
# Resources are organized by category for better readability and maintenance.
# ============================================================================

# ============================================================================
# SSH Key Management
# ============================================================================

resource "hcloud_ssh_key" "landing_zone_key" {
  name       = "${local.resource_prefix}-ssh-key"
  public_key = data.local_file.ssh_public_key.content
  labels     = local.common_labels
}

# ============================================================================
# Network Infrastructure
# ============================================================================

resource "hcloud_network" "main" {
  name     = "${local.resource_prefix}-network"
  ip_range = var.network_cidr
  labels   = local.common_labels
}

# Management Subnet (for bastion, management tools)
resource "hcloud_network_subnet" "management" {
  type         = "cloud"
  network_id   = hcloud_network.main.id
  network_zone = var.network_zone
  ip_range     = var.subnet_management_cidr
}

# Application Subnet (for app servers)
resource "hcloud_network_subnet" "application" {
  type         = "cloud"
  network_id   = hcloud_network.main.id
  network_zone = var.network_zone
  ip_range     = var.subnet_application_cidr
}

# Services Subnet (for shared services)
resource "hcloud_network_subnet" "services" {
  type         = "cloud"
  network_id   = hcloud_network.main.id
  network_zone = var.network_zone
  ip_range     = var.subnet_services_cidr
}

# DMZ Subnet (for public-facing services)
resource "hcloud_network_subnet" "dmz" {
  type         = "cloud"
  network_id   = hcloud_network.main.id
  network_zone = var.network_zone
  ip_range     = var.subnet_dmz_cidr
}

# ============================================================================
# Firewall Rules
# ============================================================================

# Bastion/Management Firewall
resource "hcloud_firewall" "bastion" {
  name   = "${local.resource_prefix}-bastion-fw"
  labels = local.common_labels

  # SSH access
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.allowed_ssh_ips
  }

  # WireGuard VPN
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "51820"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # ICMP (ping)
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Consul server ports from private network
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8300"
    source_ips = [var.network_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8301"
    source_ips = [var.network_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "8301"
    source_ips = [var.network_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8500"
    source_ips = [var.network_cidr, "192.168.100.0/24"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8502"
    source_ips = [var.network_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8600"
    source_ips = [var.network_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "8600"
    source_ips = [var.network_cidr]
  }

  # Allow all outbound
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
}

# Application Firewall
resource "hcloud_firewall" "application" {
  name   = "${local.resource_prefix}-app-fw"
  labels = local.common_labels

  # HTTP/HTTPS from anywhere
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # SSH only from private network
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = [var.network_cidr]
  }

  # Consul agent ports from private network
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8301"
    source_ips = [var.network_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "8301"
    source_ips = [var.network_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8502"
    source_ips = [var.network_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8600"
    source_ips = [var.network_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "8600"
    source_ips = [var.network_cidr]
  }

  # Envoy sidecar mesh traffic
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "20000"
    source_ips = [var.network_cidr]
  }

  # ICMP (ping)
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Allow all outbound
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
}

# Database Firewall (most restrictive)
resource "hcloud_firewall" "database" {
  name   = "${local.resource_prefix}-db-fw"
  labels = local.common_labels

  # PostgreSQL from private network only
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "5432"
    source_ips = [var.network_cidr]
  }

  # MySQL from private network only
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "3306"
    source_ips = [var.network_cidr]
  }

  # MongoDB from private network only
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "27017"
    source_ips = [var.network_cidr]
  }

  # Redis from private network only
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6379"
    source_ips = [var.network_cidr]
  }

  # SSH only from management subnet
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = [var.subnet_management_cidr]
  }

  # Consul agent ports from private network
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8301"
    source_ips = [var.network_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "8301"
    source_ips = [var.network_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8502"
    source_ips = [var.network_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "8600"
    source_ips = [var.network_cidr]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "8600"
    source_ips = [var.network_cidr]
  }

  # Envoy sidecar mesh traffic
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "20000"
    source_ips = [var.network_cidr]
  }

  # ICMP (ping) from private network
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = [var.network_cidr]
  }

  # Allow outbound to private network
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "any"
    destination_ips = [var.network_cidr]
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "any"
    destination_ips = [var.network_cidr]
  }

  # Allow outbound HTTPS for updates
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "443"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "80"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
}

# ============================================================================
# Placement Groups (High Availability)
# ============================================================================

resource "hcloud_placement_group" "management" {
  name   = "${local.resource_prefix}-management-pg"
  type   = "spread"
  labels = local.common_labels
}

resource "hcloud_placement_group" "application" {
  name   = "${local.resource_prefix}-application-pg"
  type   = "spread"
  labels = local.common_labels
}

resource "hcloud_placement_group" "database" {
  name   = "${local.resource_prefix}-database-pg"
  type   = "spread"
  labels = local.common_labels
}

# ============================================================================
# Compute Resources - Bastion Host
# ============================================================================

resource "hcloud_server" "bastion" {
  name               = "${local.resource_prefix}-bastion"
  server_type        = var.bastion_server_type
  image              = var.server_image
  location           = var.primary_location
  ssh_keys           = [hcloud_ssh_key.landing_zone_key.id]
  firewall_ids       = [hcloud_firewall.bastion.id]
  placement_group_id = hcloud_placement_group.management.id
  labels             = merge(local.common_labels, { "role" = "bastion" })

  network {
    network_id = hcloud_network.main.id
    ip         = var.bastion_private_ip
  }

  user_data = templatefile("${path.module}/templates/bastion-cloud-init.tftpl", {
    datacenter       = var.environment
    consul_bind_addr = var.bastion_private_ip
    ssh_public_key   = data.local_file.ssh_public_key.content
    consul_version   = var.consul_version
    hostname         = "${local.resource_prefix}-bastion"
  })

  lifecycle {
    ignore_changes = [
      user_data,
    ]
  }
}

# ============================================================================
# Compute Resources - Application Servers
# ============================================================================

resource "hcloud_server" "application" {
  count = var.application_server_count

  name               = "${local.resource_prefix}-app-${count.index + 1}"
  server_type        = var.application_server_type
  image              = var.server_image
  location           = var.primary_location
  ssh_keys           = [hcloud_ssh_key.landing_zone_key.id]
  firewall_ids       = [hcloud_firewall.application.id]
  placement_group_id = hcloud_placement_group.application.id
  labels             = merge(local.common_labels, { "role" = "application" })

  network {
    network_id = hcloud_network.main.id
  }

  user_data = templatefile("${path.module}/templates/application-cloud-init.tftpl", {
    datacenter        = var.environment
    consul_retry_join = local.consul_retry_join
    ssh_public_key    = data.local_file.ssh_public_key.content
    consul_version    = var.consul_version
    envoy_version     = var.envoy_version
    hostname          = "${local.resource_prefix}-app-${count.index + 1}"
    service_id        = "web-${count.index + 1}"
    instance_number   = "${count.index + 1}"
    instance_tag      = "instance-${count.index + 1}"
    environment       = var.environment
  })

  lifecycle {
    ignore_changes = [
      user_data,
    ]
  }
}

# ============================================================================
# Compute Resources - Database Servers
# ============================================================================

resource "hcloud_server" "database" {
  count = var.database_server_count

  name               = "${local.resource_prefix}-db-${count.index + 1}"
  server_type        = var.database_server_type
  image              = var.server_image
  location           = var.primary_location
  ssh_keys           = [hcloud_ssh_key.landing_zone_key.id]
  firewall_ids       = [hcloud_firewall.database.id]
  placement_group_id = hcloud_placement_group.database.id
  labels             = merge(local.common_labels, { "role" = "database" })

  network {
    network_id = hcloud_network.main.id
  }

  user_data = templatefile("${path.module}/templates/database-cloud-init.tftpl", {
    datacenter        = var.environment
    consul_retry_join = local.consul_retry_join
    ssh_public_key    = data.local_file.ssh_public_key.content
    consul_version    = var.consul_version
    envoy_version     = var.envoy_version
    hostname          = "${local.resource_prefix}-db-${count.index + 1}"
    service_id        = "postgres-${count.index + 1}"
    instance_number   = "${count.index + 1}"
    instance_tag      = "instance-${count.index + 1}"
    environment       = var.environment
    network_cidr      = var.network_cidr
  })

  lifecycle {
    ignore_changes = [
      user_data,
    ]
  }
}
