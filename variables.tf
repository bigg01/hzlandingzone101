# ============================================================================
# Core Variables
# ============================================================================

variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "landing-zone"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# ============================================================================
# Network Configuration
# ============================================================================

variable "network_zone" {
  description = "Network zone (eu-central or us-east)"
  type        = string
  default     = "eu-central"

  validation {
    condition     = contains(["eu-central", "us-east"], var.network_zone)
    error_message = "Network zone must be either 'eu-central' or 'us-east'."
  }
}

variable "primary_location" {
  description = "Primary Hetzner datacenter location"
  type        = string
  default     = "nbg1"

  validation {
    condition     = contains(["fsn1", "nbg1", "hel1", "ash", "hil"], var.primary_location)
    error_message = "Primary location must be one of: fsn1, nbg1, hel1, ash, hil."
  }
}

variable "network_cidr" {
  description = "CIDR block for the main network"
  type        = string
  default     = "172.16.0.0/16"

  validation {
    condition     = can(cidrhost(var.network_cidr, 0))
    error_message = "Network CIDR must be a valid IPv4 CIDR block."
  }
}

# ============================================================================
# Subnet Configuration
# ============================================================================

variable "subnet_management_cidr" {
  description = "CIDR block for management subnet"
  type        = string
  default     = "172.16.0.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_management_cidr, 0))
    error_message = "Management subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "subnet_application_cidr" {
  description = "CIDR block for application subnet"
  type        = string
  default     = "172.16.1.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_application_cidr, 0))
    error_message = "Application subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "subnet_services_cidr" {
  description = "CIDR block for services subnet"
  type        = string
  default     = "172.16.2.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_services_cidr, 0))
    error_message = "Services subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "subnet_dmz_cidr" {
  description = "CIDR block for DMZ subnet"
  type        = string
  default     = "172.16.10.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_dmz_cidr, 0))
    error_message = "DMZ subnet CIDR must be a valid IPv4 CIDR block."
  }
}

# ============================================================================
# Security Configuration
# ============================================================================

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
  default     = "./id_ed25519_hetzner_cloud_k3s.pub"
}

variable "allowed_ssh_ips" {
  description = "List of IP addresses allowed to SSH (CIDR notation)"
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]

  validation {
    condition = alltrue([
      for ip in var.allowed_ssh_ips : can(cidrhost(ip, 0))
    ])
    error_message = "All allowed SSH IPs must be valid CIDR blocks."
  }
}

# ============================================================================
# Tagging
# ============================================================================

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy   = "Terraform"
    Environment = "Landing-Zone"
  }
}

# ============================================================================
# Server Configuration
# ============================================================================

variable "application_server_count" {
  description = "Number of application servers to create"
  type        = number
  default     = 1

  validation {
    condition     = var.application_server_count >= 0 && var.application_server_count <= 10
    error_message = "Application server count must be between 0 and 10."
  }
}

variable "database_server_count" {
  description = "Number of database servers to create"
  type        = number
  default     = 1

  validation {
    condition     = var.database_server_count >= 0 && var.database_server_count <= 10
    error_message = "Database server count must be between 0 and 10."
  }
}

variable "bastion_server_type" {
  description = "Server type for bastion host"
  type        = string
  default     = "cx22"
}

variable "application_server_type" {
  description = "Server type for application servers"
  type        = string
  default     = "cx22"
}

variable "database_server_type" {
  description = "Server type for database servers"
  type        = string
  default     = "cx22"
}

variable "server_image" {
  description = "OS image for servers"
  type        = string
  default     = "ubuntu-24.04"
}

# ============================================================================
# Consul Configuration
# ============================================================================

variable "consul_version" {
  description = "Version of Consul to install"
  type        = string
  default     = "1.17.0"
}

variable "envoy_version" {
  description = "Version of Envoy to install"
  type        = string
  default     = "1.28.0"
}

variable "bastion_private_ip" {
  description = "Static private IP for bastion/consul server"
  type        = string
  default     = "172.16.0.10"

  validation {
    condition     = can(regex("^172\\.16\\.0\\.", var.bastion_private_ip))
    error_message = "Bastion private IP must be in the 172.16.0.0/24 subnet."
  }
}
