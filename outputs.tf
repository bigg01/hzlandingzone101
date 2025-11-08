# ============================================================================
# Network Outputs
# ============================================================================

output "network_id" {
  description = "ID of the main network"
  value       = hcloud_network.main.id
}

output "network_name" {
  description = "Name of the main network"
  value       = hcloud_network.main.name
}

output "network_ip_range" {
  description = "IP range of the main network"
  value       = hcloud_network.main.ip_range
}

output "subnet_management_ip_range" {
  description = "Management subnet IP range"
  value       = hcloud_network_subnet.management.ip_range
}

output "subnet_application_ip_range" {
  description = "Application subnet IP range"
  value       = hcloud_network_subnet.application.ip_range
}

output "subnet_services_ip_range" {
  description = "Services subnet IP range"
  value       = hcloud_network_subnet.services.ip_range
}

output "subnet_dmz_ip_range" {
  description = "DMZ subnet IP range"
  value       = hcloud_network_subnet.dmz.ip_range
}

# ============================================================================
# Bastion Outputs
# ============================================================================

output "bastion_public_ip" {
  description = "Public IP address of the bastion host"
  value       = hcloud_server.bastion.ipv4_address
}

output "bastion_private_ip" {
  description = "Private IP address of the bastion host"
  value       = [for net in hcloud_server.bastion.network : net.ip][0]
}

output "bastion_server_id" {
  description = "ID of the bastion server"
  value       = hcloud_server.bastion.id
}

output "bastion_ssh_command" {
  description = "SSH command to connect to bastion"
  value       = "ssh -i ${var.ssh_public_key_path} admin@${hcloud_server.bastion.ipv4_address}"
}

output "wireguard_info_command" {
  description = "Command to retrieve WireGuard configuration from bastion"
  value       = "ssh -i ${var.ssh_public_key_path} admin@${hcloud_server.bastion.ipv4_address} 'cat /root/wireguard-info.txt && cat /etc/wireguard/wg0.conf'"
}

# ============================================================================
# Security Outputs
# ============================================================================

output "ssh_key_id" {
  description = "ID of the SSH key"
  value       = hcloud_ssh_key.landing_zone_key.id
}

output "firewall_ids" {
  description = "Map of firewall names to IDs"
  value = {
    bastion     = hcloud_firewall.bastion.id
    application = hcloud_firewall.application.id
    database    = hcloud_firewall.database.id
  }
}

# ============================================================================
# Placement Group Outputs
# ============================================================================

output "placement_group_ids" {
  description = "Map of placement group names to IDs"
  value = {
    management  = hcloud_placement_group.management.id
    application = hcloud_placement_group.application.id
    database    = hcloud_placement_group.database.id
  }
}

# ============================================================================
# General Outputs
# ============================================================================

output "resource_prefix" {
  description = "Prefix used for all resources"
  value       = local.resource_prefix
}

# ============================================================================
# Server Outputs
# ============================================================================

output "application_server_ips" {
  description = "Private IPs of application servers"
  value       = var.application_server_count > 0 ? [for s in hcloud_server.application : [for net in s.network : net.ip][0]] : []
}

output "database_server_ips" {
  description = "Private IPs of database servers"
  value       = var.database_server_count > 0 ? [for s in hcloud_server.database : [for net in s.network : net.ip][0]] : []
}

# ============================================================================
# Consul Outputs
# ============================================================================

output "consul_ui_url" {
  description = "URL to access Consul UI"
  value       = "http://${hcloud_server.bastion.ipv4_address}:8500/ui"
}

output "consul_datacenter" {
  description = "Consul datacenter name"
  value       = var.environment
}

output "consul_server_ip" {
  description = "Consul server IP (bastion)"
  value       = var.bastion_private_ip
}

output "consul_management_commands" {
  description = "Common Consul management commands"
  value       = <<-EOT
    # Check cluster status
    ssh -i ${var.ssh_public_key_path} admin@${hcloud_server.bastion.ipv4_address} 'consul members'
    
    # List services
    ssh -i ${var.ssh_public_key_path} admin@${hcloud_server.bastion.ipv4_address} 'consul catalog services'
    
    # View intentions
    ssh -i ${var.ssh_public_key_path} admin@${hcloud_server.bastion.ipv4_address} 'consul intention list'
    
    # Setup service mesh policies
    ssh -i ${var.ssh_public_key_path} admin@${hcloud_server.bastion.ipv4_address} '/usr/local/bin/setup-consul-intentions.sh'
    
    # Use management script
    ./consul-manage.sh ${hcloud_server.bastion.ipv4_address}
    
    # Access Consul UI
    Open: http://${hcloud_server.bastion.ipv4_address}:8500/ui
  EOT
}

output "service_mesh_summary" {
  description = "Consul Service Mesh deployment summary"
  value       = <<-EOT
    ╔════════════════════════════════════════════════════════════╗
    ║           Consul Service Mesh Enabled                      ║
    ╚════════════════════════════════════════════════════════════╝
    
    📊 Consul Server:    ${hcloud_server.bastion.ipv4_address}:8500
    🌐 Datacenter:       ${var.environment}
    🔒 Service Mesh:     Enabled (mTLS ready)
    
    📋 Registered Services:
       • web       (${var.application_server_count} instance${var.application_server_count > 1 ? "s" : ""})
       • postgres  (${var.database_server_count} instance${var.database_server_count > 1 ? "s" : ""})
    
    🎯 Next Steps:
       1. Configure service intentions (access policies):
          ssh admin@${hcloud_server.bastion.ipv4_address} '/usr/local/bin/setup-consul-intentions.sh'
       
       2. Access Consul UI:
          http://${hcloud_server.bastion.ipv4_address}:8500/ui
       
       3. Check service health:
          ./consul-manage.sh ${hcloud_server.bastion.ipv4_address}
       
       4. Enable zero-trust networking:
          ssh admin@${hcloud_server.bastion.ipv4_address} "consul intention create -deny '*' '*'"
          ssh admin@${hcloud_server.bastion.ipv4_address} "consul intention create -allow web postgres"
    
    📚 Documentation:
       • MICRO-SEGMENTATION-GUIDE.md (Option 3)
       • SERVICE-MESH-VMS.md
  EOT
}
