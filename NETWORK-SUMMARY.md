# Network Configuration Summary

## IP Address Scheme

### 🖥️ Virtual Machine Network: **172.16.0.0/16**
All Hetzner Cloud virtual machines use this range.

| Subnet | CIDR | Purpose | Example Hosts |
|--------|------|---------|---------------|
| Management | 172.16.0.0/24 | Bastion, monitoring | 172.16.0.10 (bastion) |
| Application | 172.16.1.0/24 | Web/app servers | 172.16.1.x (auto) |
| Services | 172.16.2.0/24 | Databases, cache | 172.16.2.x (auto) |
| DMZ | 172.16.10.0/24 | Public services | 172.16.10.x |

### 🔐 VPN Network: **192.168.100.0/24**
WireGuard VPN clients connect to this network.

| Host | IP | Description |
|------|-----|-------------|
| VPN Server | 192.168.100.1 | Bastion's WireGuard interface |
| VPN Clients | 192.168.100.2-254 | Your laptops, workstations, etc. |

## Why This Configuration?

### ✅ Benefits

**172.16.x.x for VMs:**
- Less common than 10.x or 192.168.x - fewer conflicts
- Won't clash with typical home networks (192.168.1.x)
- Won't clash with corporate VPNs (10.x.x.x)
- RFC 1918 compliant private addressing

**192.168.100.x for VPN:**
- Clearly separated from VM network
- Easy to identify VPN vs VM traffic in logs
- .100 subnet avoids most common home networks (.0, .1, .2)
- RFC 1918 compliant

### 🔄 Network Separation

```
Your Laptop (192.168.100.2)
       │
       │ WireGuard Encrypted Tunnel
       │
       ▼
Bastion WireGuard (192.168.100.1)
       │
       │ Routing/NAT
       │
       ▼
Bastion VM IP (172.16.0.10)
       │
       │ Hetzner Private Network
       │
       ├──► App Servers (172.16.1.x)
       ├──► Databases (172.16.2.x)
       └──► Other Services (172.16.x.x)
```

## VPN Client Configuration

Your `wg0-client.conf` should look like:

```ini
[Interface]
PrivateKey = <your-private-key>
Address = 192.168.100.2/32  # Your VPN IP
DNS = 1.1.1.1

[Peer]
PublicKey = <bastion-public-key>
Endpoint = <bastion-public-ip>:51820
AllowedIPs = 192.168.100.0/24, 172.16.0.0/16  # VPN + VM networks
PersistentKeepalive = 25
```

### What the AllowedIPs means:
- `192.168.100.0/24` - Route VPN traffic through tunnel
- `172.16.0.0/16` - Route all VM network traffic through tunnel
- Everything else uses your normal internet connection (split tunnel)

## Quick Access Guide

### From Your VPN Client (192.168.100.2)

```bash
# Connect to VPN
sudo wg-quick up ~/.wireguard/wg0-client.conf

# Test VPN connectivity
ping 192.168.100.1  # Bastion's VPN interface

# Access bastion via VM network
ssh admin@172.16.0.10

# Access app servers
ssh admin@172.16.1.x

# Access database servers
ssh admin@172.16.2.x

# Connect to database
psql -h 172.16.2.10 -U app_user -d app_db
```

### Firewall Rules

**Management Subnet (172.16.0.0/24):**
- ✅ SSH (22) from anywhere
- ✅ WireGuard (51820/udp) from anywhere
- ✅ All outbound

**Application Subnet (172.16.1.0/24):**
- ✅ HTTP/HTTPS (80/443) from anywhere
- ✅ SSH (22) from 172.16.0.0/16 only

**Services Subnet (172.16.2.0/24):**
- ✅ Database ports (5432, 3306, 27017, 6379) from 172.16.0.0/16 only
- ✅ SSH (22) from 172.16.0.0/24 only (management subnet)

## Common Tasks

### Add New VPN Client

```bash
# Run the setup script
./setup-vpn-client.sh

# Or manually:
# 1. Generate keys
wg genkey | tee client-privatekey | wg pubkey > client-publickey

# 2. Create config with IP 192.168.100.3 (next available)

# 3. Add to bastion
ssh admin@<bastion-ip>
sudo wg set wg0 peer <client-public-key> allowed-ips 192.168.100.3/32
```

### Deploy New Application Server

The server will automatically get an IP from the 172.16.1.0/24 subnet.

```bash
# Access via VPN
ssh admin@172.16.1.x

# Application should connect to database at:
DATABASE_URL=postgresql://app_user:password@172.16.2.10:5432/app_db
```

### Deploy New Database Server

The server will automatically get an IP from the 172.16.2.0/24 subnet.

```bash
# Access via bastion (or VPN)
ssh admin@172.16.2.x

# Configure PostgreSQL to listen on 172.16.2.x
# (Already done via cloud-init)
```

## Troubleshooting

### Can't connect to VPN
```bash
# Check WireGuard is running
sudo wg show

# Test bastion reachability
ping <bastion-public-ip>
nc -u <bastion-public-ip> 51820
```

### Can't reach VMs from VPN
```bash
# Verify AllowedIPs includes 172.16.0.0/16
cat ~/.wireguard/wg0-client.conf | grep AllowedIPs

# Test VPN connectivity
ping 192.168.100.1

# Test bastion VM IP
ping 172.16.0.10

# Check routing on bastion
ssh admin@<bastion-public-ip>
sudo sysctl net.ipv4.ip_forward  # Should be 1
sudo iptables -t nat -L -n -v    # Check MASQUERADE rule
```

### Routing Conflicts

**Problem**: Local network uses 172.16.x.x
**Solution**: Change VM network to 10.0.0.0/16 or use different 172.x subnet

**Problem**: Local network uses 192.168.100.x
**Solution**: Change VPN to 192.168.101.x in bastion's wg0.conf

## Migration from Previous Setup

If migrating from 10.0.0.0/16 or 192.168.0.0/16:

1. **Backup** current configuration
2. **Update** terraform.tfvars (no changes needed - IPs are in main.tf)
3. **Destroy** old infrastructure: `terraform destroy`
4. **Apply** new configuration: `terraform apply`
5. **Update** VPN clients with new AllowedIPs
6. **Update** application configs with new database IPs
7. **Test** connectivity

## Security Notes

### Network Isolation
- VPN network (192.168.100.x) is separate from VM network (172.16.x.x)
- All traffic between networks goes through bastion (single control point)
- WireGuard provides encryption between VPN clients and bastion

### Best Practices
1. ✅ Always use VPN for management access
2. ✅ Use bastion as jump host for database access
3. ✅ Keep databases in services subnet (172.16.2.x)
4. ✅ Restrict database SSH to management subnet only
5. ✅ Use application-level firewalls too (ufw, iptables)
6. ✅ Monitor access logs regularly
7. ✅ Rotate VPN and SSH keys periodically

## Quick Reference

```bash
# Network Ranges
VM Network:   172.16.0.0/16
VPN Network:  192.168.100.0/24

# Key IPs
Bastion VM:   172.16.0.10
Bastion VPN:  192.168.100.1
Your VPN:     192.168.100.2 (or higher)

# Connect VPN
sudo wg-quick up ~/.wireguard/wg0-client.conf

# Access bastion
ssh admin@172.16.0.10

# Test connectivity
ping 192.168.100.1   # VPN server
ping 172.16.0.10      # Bastion VM
ping 172.16.1.x       # App server
ping 172.16.2.x       # Database server
```

## Documentation Files

- **main.tf** - Terraform infrastructure configuration
- **NETWORK-PLAN.md** - Detailed network documentation
- **client-setup-guide.md** - Complete VPN client setup guide
- **setup-vpn-client.sh** - Automated VPN client setup script

---
Last Updated: November 8, 2025
